<?php

namespace App\Http\Controllers\Api;

use App\Actions\Payables\PayPayable;
use App\Actions\Receivables\ReceiveInstallment;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Controller;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Agreement;
use App\Models\Category;
use App\Models\Installment;
use App\Models\Payable;
use App\Models\ReconciledTransaction;
use App\Services\OfxParserService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class OfxReconciliationController extends Controller
{
    public function __construct(
        private readonly OfxParserService $parser,
        private readonly PayPayable $payPayable,
        private readonly ReceiveInstallment $receiveInstallment,
    ) {}

    public function parse(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);

        $request->validate([
            'account_id' => ['required', 'integer'],
            'ofx_content' => ['required_without:ofx_file', 'string', 'max:10485760'],
            'ofx_file' => ['required_without:ofx_content', 'file', 'max:10240'],
        ]);

        $account = Account::query()->where('space_id', $spaceModel->id)->findOrFail($request->integer('account_id'));

        $content = $request->hasFile('ofx_file')
            ? file_get_contents($request->file('ofx_file')->getRealPath())
            : (string) $request->input('ofx_content');

        try {
            $parsed = $this->parser->parse($content);
        } catch (\Throwable) {
            return response()->json([
                'message' => 'Nenhuma transação válida encontrada no arquivo OFX.',
                'errors' => ['ofx_file' => ['Arquivo OFX inválido, vazio ou malformado.']],
            ], 422);
        }

        if (empty($parsed)) {
            return response()->json([
                'message' => 'Nenhuma transação válida encontrada no arquivo OFX.',
                'errors' => ['ofx_file' => ['O arquivo OFX não contém transações bancárias (<STMTTRN>).']],
            ], 422);
        }

        // FITIDs já conciliados
        $fitids = collect($parsed)->pluck('fitid')->filter()->values();
        $alreadyReconciled = ReconciledTransaction::query()
            ->where('space_id', $spaceModel->id)
            ->where('account_id', $account->id)
            ->whereIn('fitid', $fitids)
            ->pluck('fitid')
            ->flip()
            ->all();

        // Contas a pagar em aberto do espaço para sugestão de correspondência
        $openPayables = Payable::query()
            ->where('space_id', $spaceModel->id)
            ->whereNotNull('amount_cents')
            ->whereRaw('paid_cents < amount_cents')
            ->whereNull('cancelled_at')
            ->with('category:id,name')
            ->get();

        // Parcelas a receber em aberto do espaço para sugestão
        $openInstallments = Installment::query()
            ->where('space_id', $spaceModel->id)
            ->whereRaw('received_cents < amount_cents')
            ->whereHas('agreement', fn ($q) => $q->whereNull('cancelled_at'))
            ->with('agreement:id,description,category_id')
            ->get();

        $preview = [];

        foreach ($parsed as $tx) {
            $isReconciled = isset($alreadyReconciled[$tx['fitid']]);
            $suggested = null;

            if (! $isReconciled) {
                $txDate = Carbon::parse($tx['posted_at']);

                if ($tx['type'] === 'debit') {
                    // Sugere Conta a Pagar com mesmo valor e vencimento próximo (+/- 7 dias)
                    $matchPayable = $openPayables->first(function (Payable $p) use ($tx, $txDate) {
                        if ($p->remainingCents() !== $tx['amount_cents']) {
                            return false;
                        }
                        $dueDate = Carbon::parse($p->due_date);

                        return abs($dueDate->diffInDays($txDate)) <= 7;
                    });

                    if ($matchPayable !== null) {
                        $suggested = [
                            'type' => 'payable',
                            'id' => $matchPayable->id,
                            'title' => $matchPayable->description,
                            'amount' => Money::fromCents($matchPayable->remainingCents() ?? 0),
                            'due_date' => $matchPayable->due_date->toDateString(),
                            'confidence' => 'high',
                        ];
                    }
                } else {
                    // Sugere Conta a Receber com mesmo valor e vencimento próximo (+/- 7 dias)
                    $matchInstallment = $openInstallments->first(function (Installment $inst) use ($tx, $txDate) {
                        if ($inst->remainingCents() !== $tx['amount_cents']) {
                            return false;
                        }
                        $dueDate = Carbon::parse($inst->due_date);

                        return abs($dueDate->diffInDays($txDate)) <= 7;
                    });

                    if ($matchInstallment !== null) {
                        $suggested = [
                            'type' => 'installment',
                            'id' => $matchInstallment->id,
                            'title' => $matchInstallment->agreement->description.' (Parc. '.$matchInstallment->number.')',
                            'amount' => Money::fromCents($matchInstallment->remainingCents()),
                            'due_date' => $matchInstallment->due_date->toDateString(),
                            'confidence' => 'high',
                        ];
                    }
                }
            }

            $preview[] = [
                'fitid' => $tx['fitid'],
                'type' => $tx['type'],
                'amount_cents' => $tx['amount_cents'],
                'amount' => Money::fromCents($tx['amount_cents']),
                'posted_at' => $tx['posted_at'],
                'memo' => $tx['memo'],
                'already_reconciled' => $isReconciled,
                'suggested_match' => $suggested,
            ];
        }

        return response()->json([
            'data' => [
                'account' => [
                    'id' => $account->id,
                    'name' => $account->name,
                ],
                'transactions_count' => count($preview),
                'already_reconciled_count' => count($alreadyReconciled),
                'transactions' => $preview,
            ],
        ]);
    }

    public function reconcile(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $user = $request->user();

        // RBAC: Usuários com perfil somente leitura/consulta (ex.: contador) são bloqueados de realizar conciliação
        $spaceModel->ensureCan($user, 'pay_payable');

        $request->validate([
            'account_id' => ['required', 'integer'],
            'transactions' => ['required', 'array', 'min:1'],
            'transactions.*.fitid' => ['required', 'string'],
            'transactions.*.action' => ['required', 'in:match_payable,match_installment,new_movement,ignore'],
            'transactions.*.amount_cents' => ['required', 'integer', 'min:1'],
            'transactions.*.posted_at' => ['required', 'date_format:Y-m-d'],
            'transactions.*.memo' => ['nullable', 'string'],
            'transactions.*.payable_id' => ['nullable', 'integer'],
            'transactions.*.installment_id' => ['nullable', 'integer'],
            'transactions.*.category_id' => ['nullable', 'integer'],
        ]);

        $account = Account::query()->where('space_id', $spaceModel->id)->findOrFail($request->integer('account_id'));

        $reconciledCount = 0;
        $ignoredCount = 0;
        $processedInRequest = [];

        DB::transaction(function () use ($request, $spaceModel, $user, $account, &$reconciledCount, &$ignoredCount, &$processedInRequest) {
            foreach ($request->input('transactions') as $txData) {
                $fitid = trim((string) $txData['fitid']);

                // Deduplica no próprio payload da requisição
                if (isset($processedInRequest[$fitid])) {
                    continue;
                }
                $processedInRequest[$fitid] = true;

                // Verifica duplicidade no banco com lock pessimista
                $exists = ReconciledTransaction::query()
                    ->where('space_id', $spaceModel->id)
                    ->where('account_id', $account->id)
                    ->where('fitid', $fitid)
                    ->lockForUpdate()
                    ->exists();

                if ($exists) {
                    continue;
                }

                $action = $txData['action'];
                $amountCents = (int) $txData['amount_cents'];
                $postedAt = $txData['posted_at'];
                $memo = $txData['memo'] ?? '';
                $movementId = null;

                // Bloqueia conciliação em período contábil fechado
                $spaceModel->ensureDateNotClosed($postedAt, 'conciliação bancária');

                if ($action === 'ignore') {
                    ReconciledTransaction::create([
                        'space_id' => $spaceModel->id,
                        'account_id' => $account->id,
                        'fitid' => $fitid,
                        'amount_cents' => $amountCents,
                        'type' => 'debit',
                        'posted_at' => $postedAt,
                        'memo' => $memo,
                        'matched_type' => 'ignored',
                    ]);
                    $ignoredCount++;

                    continue;
                }

                if ($action === 'match_payable' && ! empty($txData['payable_id'])) {
                    $payableId = (int) $txData['payable_id'];
                    // IDOR Protection: garante que a conta a pagar pertence ao espaço
                    Payable::query()->where('space_id', $spaceModel->id)->findOrFail($payableId);

                    $idemKey = 'ofx-pay-'.$fitid.'-'.Str::random(6);
                    $this->payPayable->handle(
                        $user,
                        $spaceModel,
                        $payableId,
                        $account->id,
                        $amountCents,
                        $postedAt,
                        $idemKey
                    );

                    $movement = AccountMovement::query()
                        ->where('account_id', $account->id)
                        ->where('effective_date', $postedAt)
                        ->latest('id')
                        ->first();
                    $movementId = $movement?->id;

                    ReconciledTransaction::create([
                        'space_id' => $spaceModel->id,
                        'account_id' => $account->id,
                        'fitid' => $fitid,
                        'amount_cents' => $amountCents,
                        'type' => 'debit',
                        'posted_at' => $postedAt,
                        'memo' => $memo,
                        'matched_type' => 'payable',
                        'matched_id' => $payableId,
                        'account_movement_id' => $movementId,
                    ]);
                    $reconciledCount++;
                } elseif ($action === 'match_installment' && ! empty($txData['installment_id'])) {
                    $installmentId = (int) $txData['installment_id'];
                    // IDOR Protection: garante que a parcela pertence ao espaço
                    Installment::query()->where('space_id', $spaceModel->id)->findOrFail($installmentId);

                    $idemKey = 'ofx-rec-'.$fitid.'-'.Str::random(6);
                    $this->receiveInstallment->handle(
                        $user,
                        $spaceModel,
                        $installmentId,
                        $account->id,
                        $amountCents,
                        $postedAt,
                        $idemKey
                    );

                    $movement = AccountMovement::query()
                        ->where('account_id', $account->id)
                        ->where('effective_date', $postedAt)
                        ->latest('id')
                        ->first();
                    $movementId = $movement?->id;

                    ReconciledTransaction::create([
                        'space_id' => $spaceModel->id,
                        'account_id' => $account->id,
                        'fitid' => $fitid,
                        'amount_cents' => $amountCents,
                        'type' => 'credit',
                        'posted_at' => $postedAt,
                        'memo' => $memo,
                        'matched_type' => 'installment',
                        'matched_id' => $installmentId,
                        'account_movement_id' => $movementId,
                    ]);
                    $reconciledCount++;
                } elseif ($action === 'new_movement') {
                    $categoryId = ! empty($txData['category_id']) ? (int) $txData['category_id'] : null;
                    if ($categoryId !== null) {
                        Category::query()->where('space_id', $spaceModel->id)->findOrFail($categoryId);
                    }

                    $isDebit = (isset($txData['type']) && $txData['type'] === 'debit') || (isset($txData['amount_cents']) && $txData['amount_cents'] > 0 && ! empty($txData['is_debit']));
                    $description = $memo !== '' ? $memo : 'Lançamento bancário avulso';

                    if ($isDebit) {
                        // Cria conta a pagar avulsa e liquida via PayPayable
                        $payable = Payable::create([
                            'space_id' => $spaceModel->id,
                            'kind' => 'single',
                            'description' => $description,
                            'payee' => 'Extrato Bancário',
                            'category_id' => $categoryId,
                            'amount_cents' => $amountCents,
                            'due_date' => $postedAt,
                        ]);

                        $idemKey = 'ofx-new-pay-'.$fitid.'-'.Str::random(6);
                        $this->payPayable->handle(
                            $user,
                            $spaceModel,
                            $payable->id,
                            $account->id,
                            $amountCents,
                            $postedAt,
                            $idemKey
                        );

                        $movement = AccountMovement::query()
                            ->where('account_id', $account->id)
                            ->where('effective_date', $postedAt)
                            ->latest('id')
                            ->first();

                        ReconciledTransaction::create([
                            'space_id' => $spaceModel->id,
                            'account_id' => $account->id,
                            'fitid' => $fitid,
                            'amount_cents' => $amountCents,
                            'type' => 'debit',
                            'posted_at' => $postedAt,
                            'memo' => $memo,
                            'matched_type' => 'new_movement_payable',
                            'matched_id' => $payable->id,
                            'account_movement_id' => $movement?->id,
                        ]);
                        $reconciledCount++;
                    } else {
                        // Cria acordo a receber avulso e liquida via ReceiveInstallment
                        $agreement = Agreement::create([
                            'space_id' => $spaceModel->id,
                            'description' => $description,
                            'payer' => 'Extrato Bancário',
                            'category_id' => $categoryId,
                            'total_cents' => $amountCents,
                            'installment_count' => 1,
                            'first_due_date' => $postedAt,
                        ]);

                        $installment = $agreement->installments()->create([
                            'space_id' => $spaceModel->id,
                            'number' => 1,
                            'amount_cents' => $amountCents,
                            'due_date' => $postedAt,
                        ]);

                        $idemKey = 'ofx-new-rec-'.$fitid.'-'.Str::random(6);
                        $this->receiveInstallment->handle(
                            $user,
                            $spaceModel,
                            $installment->id,
                            $account->id,
                            $amountCents,
                            $postedAt,
                            $idemKey
                        );

                        $movement = AccountMovement::query()
                            ->where('account_id', $account->id)
                            ->where('effective_date', $postedAt)
                            ->latest('id')
                            ->first();

                        ReconciledTransaction::create([
                            'space_id' => $spaceModel->id,
                            'account_id' => $account->id,
                            'fitid' => $fitid,
                            'amount_cents' => $amountCents,
                            'type' => 'credit',
                            'posted_at' => $postedAt,
                            'memo' => $memo,
                            'matched_type' => 'new_movement_agreement',
                            'matched_id' => $agreement->id,
                            'account_movement_id' => $movement?->id,
                        ]);
                        $reconciledCount++;
                    }
                }
            }
        });

        return response()->json([
            'message' => 'Conciliação processada com sucesso.',
            'data' => [
                'reconciled_count' => $reconciledCount,
                'ignored_count' => $ignoredCount,
            ],
        ]);
    }
}
