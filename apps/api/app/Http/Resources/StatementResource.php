<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\AccountMovement;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin AccountMovement */
class StatementResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $direction = $this->amount_cents >= 0 ? 'credit' : 'debit';
        $type = $this->resolveType();
        $description = $this->resolveDescription($type);
        $category = $this->category ?? $this->receipt?->installment?->agreement?->category ?? $this->payment?->payable?->category;

        return [
            'id' => $this->id,
            'account_id' => $this->account_id,
            'account_name' => $this->account?->name ?? 'Conta',
            'category_id' => $category?->id,
            'category' => $category ? new CategoryResource($category) : null,
            'effective_date' => $this->effective_date->toDateString(),
            'amount' => Money::fromCents(abs($this->amount_cents)),
            'raw_amount_cents' => $this->amount_cents,
            'direction' => $direction,
            'type' => $type,
            'description' => $description,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }

    private function resolveType(): string
    {
        if ($this->receipt_id) {
            return 'receipt';
        }
        if ($this->receipt_reversal_id) {
            return 'receipt_reversal';
        }
        if ($this->payment_id) {
            return 'payment';
        }
        if ($this->payment_reversal_id) {
            return 'payment_reversal';
        }
        if ($this->transfer_id) {
            return 'transfer';
        }
        if ($this->loan_disbursement_id) {
            return 'loan_disbursement';
        }

        return 'movement';
    }

    private function resolveDescription(string $type): string
    {
        return match ($type) {
            'receipt' => $this->receipt?->installment?->agreement?->description
                ? 'Recebimento: '.$this->receipt->installment->agreement->description
                : 'Recebimento',
            'receipt_reversal' => $this->receiptReversal?->reason
                ? 'Estorno de recebimento: '.$this->receiptReversal->reason
                : 'Estorno de recebimento',
            'payment' => $this->payment?->payable?->description
                ? 'Pagamento: '.$this->payment->payable->description
                : 'Pagamento',
            'payment_reversal' => $this->paymentReversal?->reason
                ? 'Estorno de pagamento: '.$this->paymentReversal->reason
                : 'Estorno de pagamento',
            'transfer' => $this->amount_cents < 0
                ? 'Transferência para '.($this->transfer?->destinationAccount?->name ?? 'conta')
                : 'Transferência de '.($this->transfer?->sourceAccount?->name ?? 'conta'),
            'loan_disbursement' => $this->loanDisbursement?->kind === 'granted'
                ? 'Empréstimo concedido: '.($this->loanDisbursement->title ?? '')
                : 'Empréstimo tomado: '.($this->loanDisbursement?->title ?? ''),
            default => 'Movimentação financeira',
        };
    }
}
