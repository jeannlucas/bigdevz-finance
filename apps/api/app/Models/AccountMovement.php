<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Movimentação efetivada da conta: entrada de recebimento, saída de
 * pagamento, transferência entre contas, ou compensação de estorno.
 */
class AccountMovement extends Model
{
    protected $fillable = [
        'account_id',
        'receipt_id',
        'receipt_reversal_id',
        'payment_id',
        'payment_reversal_id',
        'transfer_id',
        'amount_cents',
        'effective_date',
    ];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'effective_date' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Transfer, $this> */
    public function transfer(): BelongsTo
    {
        return $this->belongsTo(Transfer::class);
    }
}
