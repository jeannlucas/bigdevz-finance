<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Payable;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Payable */
class PayableResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $remaining = $this->remainingCents();

        return [
            'id' => $this->id,
            'space_id' => $this->space_id,
            'kind' => $this->kind,
            'description' => $this->description,
            'payee' => $this->payee,
            // Fatura sem total: nulo ("valor a informar"), nunca "0.00".
            'amount' => $this->amount_cents === null ? null : Money::fromCents($this->amount_cents),
            'paid' => Money::fromCents($this->paid_cents),
            'remaining' => $remaining === null ? null : Money::fromCents($remaining),
            'due_date' => $this->due_date->toDateString(),
            'status' => $this->status(),
            'overdue' => $this->isOverdue(),
            'plan' => $this->plan_id === null ? null : [
                'id' => $this->plan_id,
                'installment_number' => $this->installment_number,
                'installment_count' => $this->whenLoaded('plan', fn () => $this->plan->installment_count),
            ],
            'recurrence_id' => $this->recurrence_id,
            'card' => $this->card_id === null ? null : $this->whenLoaded('card', fn () => ['id' => $this->card->id, 'name' => $this->card->name], ['id' => $this->card_id]),
            'cycle' => $this->cycle?->toDateString(),
            'edited_at' => $this->edited_at?->toIso8601String(),
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancel_reason' => $this->cancel_reason,
            'payments' => PaymentResource::collection($this->whenLoaded('payments')),
        ];
    }
}
