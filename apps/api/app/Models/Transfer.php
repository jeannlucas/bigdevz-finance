<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Transfer extends Model
{
    protected $fillable = [
        'space_id',
        'destination_space_id',
        'user_id',
        'source_account_id',
        'destination_account_id',
        'amount_cents',
        'transferred_at',
        'notes',
    ];

    protected function casts(): array
    {
        return [
            'space_id' => 'integer',
            'destination_space_id' => 'integer',
            'amount_cents' => 'integer',
            'transferred_at' => 'date:Y-m-d',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Transfer $transfer): void {
            if ($transfer->destination_space_id === null) {
                $transfer->destination_space_id = $transfer->space_id;
            }
        });
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

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
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

    /** @return HasMany<AccountMovement, $this> */
    public function movements(): HasMany
    {
        return $this->hasMany(AccountMovement::class);
    }

    /** @return HasOne<TransferReversal, $this> */
    public function reversal(): HasOne
    {
        return $this->hasOne(TransferReversal::class);
    }

    public function isReversed(): bool
    {
        return $this->reversal()->exists();
    }

    public function isCrossSpace(): bool
    {
        return $this->destination_space_id !== null && $this->destination_space_id !== $this->space_id;
    }
}
