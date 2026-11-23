<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Agreement;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Totais derivados das parcelas. Exige installments carregadas.
 *
 * @mixin Agreement
 */
class AgreementResource extends JsonResource
{
    public bool $withInstallments = false;

    public function toArray(Request $request): array
    {
        $installments = $this->installments;
        $remaining = $this->total_cents !== null
            ? Money::fromCents($this->total_cents - $installments->sum('received_cents'))
            : Money::sum($installments->map(fn ($item) => $item->remainingCents() ?? 0));
        $next = $installments->first(fn ($item) => $item->amount_cents === null || ($item->remainingCents() !== null && $item->remainingCents() > 0));

        return [
            'id' => $this->id,
            'space_id' => $this->space_id,
            'kind' => $this->kind ?? 'installment',
            'is_variable' => (bool) $this->is_variable,
            'amount' => $this->amount_cents !== null ? Money::fromCents($this->amount_cents) : null,
            'estimated_amount' => $this->estimated_amount_cents !== null ? Money::fromCents($this->estimated_amount_cents) : null,
            'start_date' => $this->start_date?->toDateString(),
            'reference_day' => $this->reference_day,
            'end_date' => $this->end_date?->toDateString(),
            'category_id' => $this->category_id,
            'category' => $this->whenLoaded('category', fn () => new CategoryResource($this->category)),
            'description' => $this->description,
            'total' => $this->total_cents !== null ? Money::fromCents($this->total_cents) : null,
            'installment_count' => $this->installment_count,
            'first_due_date' => $this->first_due_date?->toDateString() ?? $this->start_date?->toDateString(),
            'received' => Money::sum($installments->pluck('received_cents')),
            'remaining' => $remaining,
            'paid_installments' => $installments->filter(fn ($item) => $item->amount_cents !== null && $item->remainingCents() === 0)->count(),
            'overdue_installments' => $installments->filter(fn ($item) => $item->isOverdue())->count(),
            'next_due_date' => $next?->due_date->toDateString(),
            'is_cancelled' => $this->isCancelled(),
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancel_reason' => $this->cancel_reason,
            'edited_at' => $this->edited_at?->toIso8601String(),
            'installments' => InstallmentResource::collection($installments),
        ];
    }

    public function withInstallments(): static
    {
        $this->withInstallments = true;

        return $this;
    }
}
