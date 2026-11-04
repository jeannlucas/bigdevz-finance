<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Loan;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Loan */
class LoanResource extends JsonResource
{
    private bool $includeInstallments = false;

    public function withInstallments(): self
    {
        $this->includeInstallments = true;

        return $this;
    }

    public function toArray(Request $request): array
    {
        $data = [
            'id' => $this->id,
            'space_id' => $this->space_id,
            'user_id' => $this->user_id,
            'kind' => $this->kind,
            'title' => $this->title,
            'counterparty' => $this->counterparty,
            'principal' => Money::fromCents($this->principal_cents),
            'total' => Money::fromCents($this->total_cents),
            'interest' => Money::fromCents($this->interestCents()),
            'paid_or_received' => Money::fromCents($this->paidOrReceivedCents()),
            'remaining' => Money::fromCents($this->remainingCents()),
            'installment_count' => $this->installment_count,
            'first_due_date' => $this->first_due_date->toDateString(),
            'disbursement_account_id' => $this->disbursement_account_id,
            'disbursed_at' => $this->disbursed_at?->toDateString(),
            'status' => $this->computedStatus(),
            'notes' => $this->notes,
            'payable_plan_id' => $this->payable_plan_id,
            'agreement_id' => $this->agreement_id,
            'created_at' => $this->created_at?->toIso8601String(),
        ];

        if ($this->includeInstallments) {
            $data['installments'] = $this->formatInstallments();
        }

        return $data;
    }

    private function formatInstallments(): array
    {
        if ($this->isTaken()) {
            $payables = $this->payablePlan?->payables ?? collect();

            return $payables->map(fn ($p) => [
                'number' => $p->installment_number,
                'amount' => Money::fromCents($p->amount_cents),
                'settled' => Money::fromCents($p->paid_cents),
                'due_date' => $p->due_date->toDateString(),
                'status' => $p->status(),
            ])->values()->all();
        }

        $installments = $this->agreement?->installments ?? collect();

        return $installments->map(fn ($i) => [
            'number' => $i->number,
            'amount' => Money::fromCents($i->amount_cents),
            'settled' => Money::fromCents($i->received_cents),
            'due_date' => $i->due_date->toDateString(),
            'status' => $i->received_cents === $i->amount_cents
                ? 'paid'
                : ($i->received_cents > 0 ? 'partial' : 'open'),
        ])->values()->all();
    }
}
