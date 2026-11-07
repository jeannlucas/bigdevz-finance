<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Transfer;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Transfer */
class TransferResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'space_id' => $this->space_id,
            'source_account_id' => $this->source_account_id,
            'destination_account_id' => $this->destination_account_id,
            'amount' => Money::fromCents($this->amount_cents),
            'transferred_at' => $this->transferred_at->toDateString(),
            'notes' => $this->notes,
            'user_id' => $this->user_id,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
