<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Movimentação efetivada da conta: entrada de recebimento, saída de
 * pagamento, ou compensação de estorno (sinal oposto, data do original).
 */
class AccountMovement extends Model
{
    protected $fillable = ['account_id', 'receipt_id', 'receipt_reversal_id', 'payment_id', 'payment_reversal_id', 'amount_cents', 'effective_date'];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'effective_date' => 'date:Y-m-d',
        ];
    }
}
