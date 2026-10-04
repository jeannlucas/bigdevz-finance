<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\ReceiveInstallment;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Controller;
use App\Http\Resources\AccountResource;
use App\Http\Resources\AgreementResource;
use App\Http\Resources\InstallmentResource;
use App\Http\Resources\ReceiptResource;
use App\Models\Account;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ReceiptController extends Controller
{
    public function store(Request $request, string $space, string $installment, ReceiveInstallment $receive): JsonResponse
    {
        $space = $this->space($request, $space);
        $installment = $space->installments()->findOrFail($installment);

        $request->merge(['idempotency_key' => $request->header('Idempotency-Key')]);
        $data = $request->validate([
            'account_id' => ['required', 'integer', 'min:1', 'max:9223372036854775807'],
            'amount' => ['required', new MoneyAmount],
            'received_on' => ['required', 'date_format:Y-m-d', 'before_or_equal:'.now(config('finance.timezone'))->toDateString()],
            'idempotency_key' => ['required', 'string', 'min:1', 'max:100'],
        ], [
            'idempotency_key.required' => 'Envie o cabeçalho Idempotency-Key para registrar o recebimento.',
            'received_on.before_or_equal' => 'A data do recebimento não pode estar no futuro.',
        ]);

        $outcome = $receive->handle(
            $request->user(), $space, $installment->id, (int) $data['account_id'],
            Money::toCents($data['amount']), $data['received_on'], $data['idempotency_key'],
        );

        $receipt = $outcome->receipt;
        $installment = $receipt->installment()->with('agreement.installments')->firstOrFail();
        $account = Account::query()->withSum('movements', 'amount_cents')->findOrFail($receipt->account_id);

        return response()->json(['data' => [
            'receipt' => new ReceiptResource($receipt),
            'installment' => new InstallmentResource($installment),
            'agreement' => new AgreementResource($installment->agreement),
            'account' => new AccountResource($account),
            'replayed' => ! $outcome->created,
        ]], $outcome->created ? 201 : 200);
    }
}
