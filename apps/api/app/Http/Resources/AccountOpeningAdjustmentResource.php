<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\AccountOpeningAdjustment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin AccountOpeningAdjustment */
class AccountOpeningAdjustmentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'account_id' => $this->account_id,
            'previous_opening_balance' => Money::fromCents($this->previous_opening_balance_cents),
            'previous_opening_balance_date' => $this->previous_opening_balance_date->toDateString(),
            'new_opening_balance' => Money::fromCents($this->new_opening_balance_cents),
            'new_opening_balance_date' => $this->new_opening_balance_date->toDateString(),
            'reason' => $this->reason,
            'user_id' => $this->user_id,
            'adjusted_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
