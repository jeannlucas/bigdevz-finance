<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Correção auditada do saldo inicial e/ou da data de abertura de uma conta. */
class AccountOpeningAdjustment extends Model
{
    protected $fillable = [
        'space_id', 'account_id', 'user_id', 'reason',
        'previous_opening_balance_cents', 'previous_opening_balance_date',
        'new_opening_balance_cents', 'new_opening_balance_date',
    ];

    protected function casts(): array
    {
        return [
            'previous_opening_balance_cents' => 'integer',
            'new_opening_balance_cents' => 'integer',
            'previous_opening_balance_date' => 'date:Y-m-d',
            'new_opening_balance_date' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Account, $this> */
    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }
}
