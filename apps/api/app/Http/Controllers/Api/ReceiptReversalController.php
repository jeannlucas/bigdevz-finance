<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Actions\Receivables\ReverseReceipt;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Api\Concerns\HandlesIdempotency;
use App\Http\Controllers\Controller;
use App\Http\Resources\AccountResource;
use App\Http\Resources\AgreementResource;
use App\Http\Resources\InstallmentResource;
use App\Http\Resources\ReceiptResource;
use App\Http\Resources\ReceiptReversalResource;
use App\Models\Account;
use App\Models\Receipt;
use App\Models\ReceiptReversal;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/** Estorno (sem substituto) e correção (estorno + substituto) de recebimentos. */
class ReceiptReversalController extends Controller
{
    use HandlesIdempotency;

    public function reverse(Request $request, string $space, string $receipt, ReverseReceipt $reverse, IdempotentOperations $keys): JsonResponse
    {
        return $this->handle($request, $space, $receipt, $reverse, $keys, correction: false);
    }

    public function correct(Request $request, string $space, string $receipt, ReverseReceipt $reverse, IdempotentOperations $keys): JsonResponse
    {
        return $this->handle($request, $space, $receipt, $reverse, $keys, correction: true);
    }

    private function handle(Request $request, string $space, string $receipt, ReverseReceipt $reverse, IdempotentOperations $keys, bool $correction): JsonResponse
    {
        $space = $this->space($request, $space);
        $receipt = $space->receipts()->findOrFail($receipt);
        $key = $this->idempotencyKey($request);

        $rules = ['reason' => ['required', 'string', 'min:3', 'max:500']];
        if ($correction) {
            $rules += [
                'account_id' => ['required', 'integer', 'min:1', 'max:9223372036854775807'],
                'amount' => ['required', new MoneyAmount],
                'received_on' => ['required', 'date_format:Y-m-d', 'before_or_equal:'.now(config('finance.timezone'))->toDateString()],
            ];
        }
        $validator = Validator::make($request->all(), $rules, [
            'reason.required' => 'Informe o motivo.',
            'reason.min' => 'Descreva o motivo com pelo menos 3 caracteres.',
            'received_on.before_or_equal' => 'A data do recebimento não pode estar no futuro.',
        ]);
        $operation = $correction ? IdempotentOperations::CORRECTION : IdempotentOperations::REVERSAL;
        if ($validator->fails()) {
            $fingerprint = ReverseReceipt::fingerprint($receipt->id, $request->input('reason'), $correction ? [
                'account_id' => $request->input('account_id'),
                'amount' => $request->input('amount'),
                'received_on' => $request->input('received_on'),
            ] : null);

            return $this->rejection($key, $keys->reject($request->user(), $space, $key, $operation, $fingerprint, $validator->errors()->toArray()));
        }
        $data = $validator->validated();

        $result = $reverse->handle($request->user(), $space, $receipt->id, $data['reason'], $key, $correction ? [
            'account_id' => (int) $data['account_id'],
            'amount_cents' => Money::toCents($data['amount']),
            'received_on' => $data['received_on'],
        ] : null);

        return $result->rejected() ? $this->rejection($key, $result) : $this->outcome($key, $result);
    }

    private function outcome(string $key, KeyedResult $result): JsonResponse
    {
        $reversal = ReceiptReversal::query()->findOrFail($result->reversalId);
        $original = Receipt::query()->with(['reversal', 'correctionOf'])->findOrFail($reversal->receipt_id);
        $replacement = $reversal->replacement_receipt_id === null ? null
            : Receipt::query()->with(['reversal', 'correctionOf'])->findOrFail($reversal->replacement_receipt_id);
        $installment = $original->installment()->with('agreement.installments')->firstOrFail();
        $accounts = Account::query()->withSum('movements', 'amount_cents')
            ->whereIn('id', array_filter([$original->account_id, $replacement?->account_id]))->orderBy('id')->get();

        return response()->json([
            'data' => [
                'reversal' => new ReceiptReversalResource($reversal),
                'original' => new ReceiptResource($original),
                'replacement' => $replacement === null ? null : new ReceiptResource($replacement),
                'installment' => new InstallmentResource($installment),
                'agreement' => new AgreementResource($installment->agreement),
                'accounts' => AccountResource::collection($accounts),
                'replayed' => $result->replayed,
            ],
            'idempotency' => $this->idempotency($key, $result),
        ], $result->replayed ? 200 : 201);
    }
}
