<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Receipt extends Model
{
    protected $fillable = [
        'space_id', 'installment_id', 'account_id', 'user_id', 'amount_cents',
        'received_on', 'idempotency_key', 'request_fingerprint',
    ];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'received_on' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Installment, $this> */
    public function installment(): BelongsTo
    {
        return $this->belongsTo(Installment::class);
    }

    /** @return BelongsTo<Account, $this> */
    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    /** @return HasOne<AccountMovement, $this> */
    public function movement(): HasOne
    {
        return $this->hasOne(AccountMovement::class);
    }
}
