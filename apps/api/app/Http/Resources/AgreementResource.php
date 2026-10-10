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
        $received = $installments->sum('received_cents');
        $next = $installments->first(fn ($item) => $item->remainingCents() > 0);

        return [
            'id' => $this->id,
            'space_id' => $this->space_id,
            'description' => $this->description,
            'total' => Money::fromCents($this->total_cents),
            'installment_count' => $this->installment_count,
            'first_due_date' => $this->first_due_date->toDateString(),
            'received' => Money::fromCents($received),
            'remaining' => Money::fromCents($this->total_cents - $received),
            'paid_installments' => $installments->filter(fn ($item) => $item->remainingCents() === 0)->count(),
            'overdue_installments' => $installments->filter(fn ($item) => $item->isOverdue())->count(),
            'next_due_date' => $next?->due_date->toDateString(),
            'installments' => InstallmentResource::collection($installments),
        ];
    }

    public function withInstallments(): static
    {
        $this->withInstallments = true;

        return $this;
    }
}
