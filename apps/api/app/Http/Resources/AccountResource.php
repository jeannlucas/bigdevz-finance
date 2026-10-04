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
        ];
    }
}
