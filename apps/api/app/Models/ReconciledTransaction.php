<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ReconciledTransaction extends Model
{
    protected $fillable = [
        'space_id',
        'account_id',
        'fitid',
        'amount_cents',
        'type',
        'posted_at',
        'memo',
        'matched_type',
        'matched_id',
        'account_movement_id',
    ];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'posted_at' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Space, $this> */
    public function space(): BelongsTo
    {
        return $this->belongsTo(Space::class);
    }

    /** @return BelongsTo<Account, $this> */
    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    /** @return BelongsTo<AccountMovement, $this> */
    public function movement(): BelongsTo
    {
        return $this->belongsTo(AccountMovement::class, 'account_movement_id');
    }
}
