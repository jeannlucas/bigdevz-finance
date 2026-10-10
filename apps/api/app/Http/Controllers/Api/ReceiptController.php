<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\ReceiveInstallment;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Api\Concerns\HandlesIdempotency;
use App\Http\Controllers\Controller;
use App\Http\Resources\AccountResource;
use App\Http\Resources\AgreementResource;
use App\Http\Resources\InstallmentResource;
use App\Http\Resources\ReceiptResource;
use App\Models\Account;
use App\Models\Receipt;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ReceiptController extends Controller
{
    use HandlesIdempotency;

    public function store(Request $request, string $space, string $installment, ReceiveInstallment $receive, IdempotentOperations $keys): JsonResponse
    {
        $space = $this->space($request, $space);
        $installment = $space->installments()->findOrFail($installment);
        $key = $this->idempotencyKey($request);

        $validator = Validator::make($request->all(), [
            'account_id' => ['required', 'integer', 'min:1', 'max:9223372036854775807'],
            'amount' => ['required', new MoneyAmount],
            'received_on' => ['required', 'date_format:Y-m-d', 'before_or_equal:'.now(config('finance.timezone'))->toDateString()],
        ], [
            'received_on.before_or_equal' => 'A data do recebimento não pode estar no futuro.',
        ]);
        if ($validator->fails()) {
            $fingerprint = ReceiveInstallment::fingerprint($installment->id, $request->input('account_id'), $request->input('amount'), $request->input('received_on'));

            return $this->rejection($key, $keys->reject($request->user(), $space, $key, IdempotentOperations::RECEIPT, $fingerprint, $validator->errors()->toArray()));
        }
        $data = $validator->validated();

        $result = $receive->handle(
            $request->user(), $space, $installment->id, (int) $data['account_id'],
            Money::toCents($data['amount']), $data['received_on'], $key,
        );
        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }

        // Num reenvio, devolve o recebimento original com a situação atual
        // (inclusive estornado), sem recriar dinheiro.
        $receipt = Receipt::query()->with(['reversal', 'correctionOf'])->findOrFail($result->receiptId);
        $installment = $receipt->installment()->with('agreement.installments')->firstOrFail();
        $account = Account::query()->withSum('movements', 'amount_cents')->findOrFail($receipt->account_id);

        return response()->json([
            'data' => [
                'receipt' => new ReceiptResource($receipt),
                'installment' => new InstallmentResource($installment),
                'agreement' => new AgreementResource($installment->agreement),
                'account' => new AccountResource($account),
                'replayed' => $result->replayed,
            ],
            'idempotency' => $this->idempotency($key, $result),
        ], $result->replayed ? 200 : 201);
    }
}
