<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Payment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Payment */
class PaymentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'payable_id' => $this->payable_id,
            'account_id' => $this->account_id,
            'amount' => Money::fromCents($this->amount_cents),
            'paid_on' => $this->paid_on->toDateString(),
            'recorded_at' => $this->created_at?->toIso8601String(),
            'status' => $this->reversal === null ? 'active' : 'reversed',
            'reversal' => $this->reversal === null ? null : [
                'id' => $this->reversal->id,
                'kind' => $this->reversal->isCorrection() ? 'correction' : 'reversal',
                'payment_id' => $this->reversal->payment_id,
                'replacement_payment_id' => $this->reversal->replacement_payment_id,
                'reason' => $this->reversal->reason,
                'user_id' => $this->reversal->user_id,
                'reversed_at' => $this->reversal->created_at?->toIso8601String(),
            ],
            'replaces_payment_id' => $this->correctionOf?->payment_id,
        ];
    }
}
