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
            'amount' => Money::fromCents($this->amount_cents),
            'start_date' => $this->start_date->toDateString(),
            'reference_day' => $this->reference_day,
            'end_date' => $this->end_date?->toDateString(),
        ];
    }
}
