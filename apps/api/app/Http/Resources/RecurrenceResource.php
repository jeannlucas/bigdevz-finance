<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Recurrence;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Recurrence */
class RecurrenceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'description' => $this->description,
            'payee' => $this->payee,
            'is_variable' => (bool) $this->is_variable,
            'amount' => $this->amount_cents === null ? null : Money::fromCents($this->amount_cents),
            'estimated_amount' => $this->estimated_amount_cents === null ? null : Money::fromCents($this->estimated_amount_cents),
            'start_date' => $this->start_date->toDateString(),
            'reference_day' => $this->reference_day,
            'end_date' => $this->end_date?->toDateString(),
        ];
    }
}
