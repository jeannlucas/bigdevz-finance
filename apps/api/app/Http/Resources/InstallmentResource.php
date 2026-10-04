<?php

namespace App\Http\Resources;

use App\Domain\Receivables\Money;
use App\Models\Installment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Installment */
class InstallmentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'agreement_id' => $this->agreement_id,
            'number' => $this->number,
            'due_date' => $this->due_date->toDateString(),
            'amount' => Money::fromCents($this->amount_cents),
            'received' => Money::fromCents($this->received_cents),
            'remaining' => Money::fromCents($this->remainingCents()),
            'status' => $this->status(),
            'overdue' => $this->isOverdue(),
            'agreement' => $this->whenLoaded('agreement', fn () => [
                'id' => $this->agreement->id,
                'description' => $this->agreement->description,
                'installment_count' => $this->agreement->installment_count,
            ]),
            'receipts' => ReceiptResource::collection($this->whenLoaded('receipts')),
        ];
    }
}
