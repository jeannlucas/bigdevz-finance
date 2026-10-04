<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Movimentação efetivada da conta. Neste checkpoint nasce só de recebimentos. */
class AccountMovement extends Model
{
    protected $fillable = ['account_id', 'receipt_id', 'amount_cents', 'effective_date'];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'effective_date' => 'date:Y-m-d',
        ];
    }
}
