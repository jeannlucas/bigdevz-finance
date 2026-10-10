<?php

namespace App\Http\Controllers\Api;

use App\Actions\Payables\PayPayable;
use App\Actions\Payables\ReversePayment;
use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Api\Concerns\HandlesIdempotency;
use App\Http\Controllers\Controller;
use App\Http\Resources\AccountResource;
use App\Http\Resources\PayableResource;
use App\Http\Resources\PaymentResource;
use App\Models\Account;
use App\Models\Payment;
use App\Models\PaymentReversal;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/** Pagamentos de obrigações, estornos e correções. */
class PaymentController extends Controller
{
    use HandlesIdempotency;

    public function store(Request $request, string $space, string $payable, PayPayable $pay, IdempotentOperations $keys): JsonResponse
    {
        $space = $this->space($request, $space);
        $model = $space->payables()->findOrFail($payable);
        $key = $this->idempotencyKey($request);
        $validator = Validator::make($request->all(), $this->rules(), $this->messages());
        if ($validator->fails()) {
            $fingerprint = PayPayable::fingerprint($model->id, $request->input('account_id'), $request->input('amount'), $request->input('paid_on'));

            return $this->rejection($key, $keys->reject($request->user(), $space, $key, IdempotentOperations::PAYMENT, $fingerprint, $validator->errors()->toArray()));
        }
        $data = $validator->validated();
        $result = $pay->handle($request->user(), $space, $model->id, (int) $data['account_id'], Money::toCents($data['amount']), $data['paid_on'], $key);
        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }
        // Reenvio: o pagamento original com a situação atual (inclusive estornado).
        $payment = Payment::query()->with(['reversal', 'correctionOf'])->findOrFail($result->ref('payment_id'));

        return response()->json([
            'data' => [
                'payment' => new PaymentResource($payment),
                'payable' => new PayableResource($payment->payable()->with(['card', 'plan'])->firstOrFail()),
                'account' => new AccountResource(Account::query()->withSum('movements', 'amount_cents')->findOrFail($payment->account_id)),
                'replayed' => $result->replayed,
            ],
            'idempotency' => $this->idempotency($key, $result),
        ], $result->replayed ? 200 : 201);
    }

    public function reverse(Request $request, string $space, string $payment, ReversePayment $reverse, IdempotentOperations $keys): JsonResponse
    {
        return $this->fix($request, $space, $payment, $reverse, $keys, false);
    }

    public function correct(Request $request, string $space, string $payment, ReversePayment $reverse, IdempotentOperations $keys): JsonResponse
    {
        return $this->fix($request, $space, $payment, $reverse, $keys, true);
    }

    private function fix(Request $request, string $space, string $payment, ReversePayment $reverse, IdempotentOperations $keys, bool $correction): JsonResponse
    {
        $space = $this->space($request, $space);
        $model = $space->payments()->findOrFail($payment);
        $key = $this->idempotencyKey($request);
        $rules = ['reason' => ['required', 'string', 'min:3', 'max:500']] + ($correction ? $this->rules() : []);
        $validator = Validator::make($request->all(), $rules, $this->messages());
        $operation = $correction ? IdempotentOperations::PAYMENT_CORRECTION : IdempotentOperations::PAYMENT_REVERSAL;
        if ($validator->fails()) {
            $fingerprint = ReversePayment::fingerprint($model->id, $request->input('reason'), $correction ? [
                'account_id' => $request->input('account_id'), 'amount' => $request->input('amount'), 'paid_on' => $request->input('paid_on'),
            ] : null);

            return $this->rejection($key, $keys->reject($request->user(), $space, $key, $operation, $fingerprint, $validator->errors()->toArray()));
        }
        $data = $validator->validated();
        $result = $reverse->handle($request->user(), $space, $model->id, $data['reason'], $key, $correction ? [
            'account_id' => (int) $data['account_id'], 'amount_cents' => Money::toCents($data['amount']), 'paid_on' => $data['paid_on'],
        ] : null);

        return $result->rejected() ? $this->rejection($key, $result) : $this->fixOutcome($key, $result);
    }

    private function fixOutcome(string $key, KeyedResult $result): JsonResponse
    {
        $reversal = PaymentReversal::query()->findOrFail($result->ref('payment_reversal_id'));
        $original = Payment::query()->with(['reversal', 'correctionOf'])->findOrFail($reversal->payment_id);
        $replacement = $reversal->replacement_payment_id === null ? null
            : Payment::query()->with(['reversal', 'correctionOf'])->findOrFail($reversal->replacement_payment_id);
        $accounts = Account::query()->withSum('movements', 'amount_cents')
            ->whereIn('id', array_filter([$original->account_id, $replacement?->account_id]))->orderBy('id')->get();

        return response()->json([
            'data' => [
                'original' => new PaymentResource($original),
                'replacement' => $replacement === null ? null : new PaymentResource($replacement),
                'payable' => new PayableResource($original->payable()->with(['card', 'plan'])->firstOrFail()),
                'accounts' => AccountResource::collection($accounts),
                'replayed' => $result->replayed,
            ],
            'idempotency' => $this->idempotency($key, $result),
        ], $result->replayed ? 200 : 201);
    }

    private function rules(): array
    {
        return [
            'account_id' => ['required', 'integer', 'min:1', 'max:9223372036854775807'],
            'amount' => ['required', new MoneyAmount],
            'paid_on' => ['required', 'date_format:Y-m-d', 'before_or_equal:'.now(config('finance.timezone'))->toDateString()],
        ];
    }

    private function messages(): array
    {
        return [
            'reason.required' => 'Informe o motivo.',
            'reason.min' => 'Descreva o motivo com pelo menos 3 caracteres.',
            'paid_on.before_or_equal' => 'A data do pagamento não pode estar no futuro.',
        ];
    }
}
