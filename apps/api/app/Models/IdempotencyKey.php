<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Decisão final de uma chave idempotente do espaço: concluída ou recusada. */
class IdempotencyKey extends Model
{
    public const COMPLETED = 'completed';

    public const REJECTED = 'rejected';

    protected $fillable = [
        'space_id', 'user_id', 'key', 'operation', 'fingerprint', 'status',
        'errors', 'receipt_id', 'receipt_reversal_id', 'account_opening_adjustment_id',
        'payable_id', 'payable_plan_id', 'recurrence_id', 'payment_id', 'payment_reversal_id',
    ];

    protected function casts(): array
    {
        return ['errors' => 'array'];
    }
}
