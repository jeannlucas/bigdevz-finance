<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class TransferReversal extends Model
{
    protected $fillable = [
        'transfer_id',
        'space_id',
        'destination_space_id',
        'source_account_id',
        'destination_account_id',
        'user_id',
        'reason',
    ];

    protected function casts(): array
    {
        return [
            'transfer_id' => 'integer',
            'space_id' => 'integer',
            'destination_space_id' => 'integer',
            'source_account_id' => 'integer',
            'destination_account_id' => 'integer',
            'user_id' => 'integer',
        ];
    }

    /** @return BelongsTo<Transfer, $this> */
    public function transfer(): BelongsTo
    {
        return $this->belongsTo(Transfer::class);
    }

    /** @return BelongsTo<Space, $this> */
    public function space(): BelongsTo
    {
        return $this->belongsTo(Space::class);
    }

    /** @return BelongsTo<Space, $this> */
    public function destinationSpace(): BelongsTo
    {
        return $this->belongsTo(Space::class, 'destination_space_id');
    }

    /** @return BelongsTo<Account, $this> */
    public function sourceAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'source_account_id');
    }

    /** @return BelongsTo<Account, $this> */
    public function destinationAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'destination_account_id');
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return HasMany<AccountMovement, $this> */
    public function movements(): HasMany
    {
        return $this->hasMany(AccountMovement::class);
    }
}
