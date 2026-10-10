<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Account;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Account */
class AccountResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'space_id' => $this->space_id,
            'name' => $this->name,
            'opening_balance' => Money::fromCents($this->opening_balance_cents),
            'opening_balance_date' => $this->opening_balance_date->toDateString(),
            'balance' => Money::fromCents($this->balanceCents()),
            'archived_at' => $this->archived_at?->toIso8601String(),
            // Limite para a data de abertura: nenhuma movimentação antes dela.
            'first_movement_date' => $this->when(
                array_key_exists('movements_min_effective_date', $this->resource->getAttributes()),
                fn () => $this->resource->getAttributes()['movements_min_effective_date'] === null
                    ? null : substr((string) $this->resource->getAttributes()['movements_min_effective_date'], 0, 10),
            ),
            'opening_adjustments' => AccountOpeningAdjustmentResource::collection($this->whenLoaded('openingAdjustments')),
        ];
    }
}
