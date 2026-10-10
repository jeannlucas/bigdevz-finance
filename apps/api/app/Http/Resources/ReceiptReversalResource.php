<?php

namespace App\Http\Resources;

use App\Models\ReceiptReversal;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin ReceiptReversal */
class ReceiptReversalResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'kind' => $this->isCorrection() ? 'correction' : 'reversal',
            'receipt_id' => $this->receipt_id,
            'replacement_receipt_id' => $this->replacement_receipt_id,
            'reason' => $this->reason,
            'user_id' => $this->user_id,
            'reversed_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
