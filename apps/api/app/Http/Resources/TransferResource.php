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
            'destination_space_id' => $this->destination_space_id ?? $this->space_id,
            'source_account_id' => $this->source_account_id,
            'destination_account_id' => $this->destination_account_id,
            'amount' => Money::fromCents($this->amount_cents),
            'transferred_at' => $this->transferred_at->toDateString(),
            'notes' => $this->notes,
            'is_cross_space' => $this->isCrossSpace(),
            'is_reversed' => $this->isReversed(),
            'reversal' => $this->reversal ? new TransferReversalResource($this->reversal) : null,
            'source_space' => $this->space ? ['id' => $this->space->id, 'name' => $this->space->name, 'kind' => $this->space->kind] : null,
            'destination_space' => $this->destinationSpace ? ['id' => $this->destinationSpace->id, 'name' => $this->destinationSpace->name, 'kind' => $this->destinationSpace->kind] : null,
            'source_account' => $this->sourceAccount ? ['id' => $this->sourceAccount->id, 'name' => $this->sourceAccount->name] : null,
            'destination_account' => $this->destinationAccount ? ['id' => $this->destinationAccount->id, 'name' => $this->destinationAccount->name] : null,
            'user_id' => $this->user_id,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
