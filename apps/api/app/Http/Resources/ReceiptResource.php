<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Receipt;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Receipt */
class ReceiptResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'installment_id' => $this->installment_id,
            'account_id' => $this->account_id,
            'amount' => Money::fromCents($this->amount_cents),
            'received_on' => $this->received_on->toDateString(),
            'recorded_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
