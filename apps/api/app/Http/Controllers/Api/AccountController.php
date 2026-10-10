<?php

namespace App\Http\Controllers\Api;

use App\Actions\Accounts\AdjustAccountOpening;
use App\Actions\Accounts\ArchiveAccount;
use App\Actions\Receivables\IdempotentOperations;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Api\Concerns\HandlesIdempotency;
use App\Http\Controllers\Controller;
use App\Http\Resources\AccountOpeningAdjustmentResource;
use App\Http\Resources\AccountResource;
use App\Models\Account;
use App\Models\AccountOpeningAdjustment;
use App\Models\Space;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Validator;

class AccountController extends Controller
{
    use HandlesIdempotency;

    /** Ativas e arquivadas; o app separa as duas por `archived_at`. */
    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        return AccountResource::collection(
            $this->withTotals($this->space($request, $space)->accounts())->orderBy('name')->orderBy('id')->get(),
        );
    }

    public function store(Request $request, string $space): JsonResponse
    {
        $space = $this->space($request, $space);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:80'],
            'opening_balance' => ['required', new MoneyAmount(positive: false)],
            'opening_balance_date' => ['required', 'date_format:Y-m-d'],
        ]);

        $account = $space->accounts()->create([
            'name' => $data['name'],
            'opening_balance_cents' => Money::toCents($data['opening_balance']),
            'opening_balance_date' => $data['opening_balance_date'],
        ]);

        return (new AccountResource($account))->response()->setStatusCode(201);
    }

    public function show(Request $request, string $space, string $account): AccountResource
    {
        return new AccountResource($this->find($this->space($request, $space), $account));
    }

    /**
     * Só identificação (nome). Abertura tem fluxo próprio, auditado; espaço e
     * dono não mudam. A mesma conta é atualizada: id, saldo e histórico ficam.
     */
    public function update(Request $request, string $space, string $account): AccountResource
    {
        $space = $this->space($request, $space);
        $model = $space->accounts()->findOrFail($account);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:80'],
            'space_id' => ['prohibited'],
            'opening_balance' => ['prohibited'],
            'opening_balance_date' => ['prohibited'],
        ], [
            'space_id.prohibited' => 'A conta não pode mudar de espaço.',
            'opening_balance.prohibited' => 'Use a correção de abertura para alterar o saldo inicial.',
            'opening_balance_date.prohibited' => 'Use a correção de abertura para alterar a data de abertura.',
        ]);
        $model->update(['name' => $data['name']]);

        return new AccountResource($this->find($space, $model->id));
    }

    /** Arquivar não muda dinheiro; serializado com recebimentos pelo lock da conta. */
    public function archive(Request $request, string $space, string $account, ArchiveAccount $archive): AccountResource
    {
        return $this->setArchived($this->space($request, $space), $account, $archive, archived: true);
    }

    public function unarchive(Request $request, string $space, string $account, ArchiveAccount $archive): AccountResource
    {
        return $this->setArchived($this->space($request, $space), $account, $archive, archived: false);
    }

    public function adjustOpening(Request $request, string $space, string $account, AdjustAccountOpening $adjust, IdempotentOperations $keys): JsonResponse
    {
        $space = $this->space($request, $space);
        $model = $space->accounts()->findOrFail($account);
        $key = $this->idempotencyKey($request);

        $validator = Validator::make($request->all(), [
            'opening_balance' => ['required', new MoneyAmount(positive: false)],
            'opening_balance_date' => ['required', 'date_format:Y-m-d'],
            'reason' => ['required', 'string', 'min:3', 'max:500'],
        ], [
            'reason.required' => 'Informe o motivo.',
            'reason.min' => 'Descreva o motivo com pelo menos 3 caracteres.',
        ]);
        if ($validator->fails()) {
            $fingerprint = AdjustAccountOpening::fingerprint($model->id, $request->input('opening_balance'), $request->input('opening_balance_date'), $request->input('reason'));

            return $this->rejection($key, $keys->reject($request->user(), $space, $key, IdempotentOperations::OPENING_ADJUSTMENT, $fingerprint, $validator->errors()->toArray()));
        }
        $data = $validator->validated();

        $result = $adjust->handle($request->user(), $space, $model->id, Money::toCents($data['opening_balance']), $data['opening_balance_date'], $data['reason'], $key);
        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }

        return response()->json([
            'data' => [
                'adjustment' => new AccountOpeningAdjustmentResource(AccountOpeningAdjustment::query()->findOrFail($result->adjustmentId)),
                'account' => new AccountResource($this->find($space, $model->id)),
                'replayed' => $result->replayed,
            ],
            'idempotency' => $this->idempotency($key, $result),
        ], $result->replayed ? 200 : 201);
    }

    private function setArchived(Space $space, string $account, ArchiveAccount $archive, bool $archived): AccountResource
    {
        $model = $space->accounts()->findOrFail($account);

        return new AccountResource($this->find($space, $archive->handle($space, $model->id, $archived)->id));
    }

    private function find(Space $space, string|int $account): Account
    {
        return $this->withTotals($space->accounts())->with('openingAdjustments')->findOrFail($account);
    }

    private function withTotals($query)
    {
        return $query->withSum('movements', 'amount_cents')->withMin('movements', 'effective_date');
    }
}
