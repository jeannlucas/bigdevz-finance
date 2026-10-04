<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Account extends Model
{
    protected $fillable = ['name', 'opening_balance_cents', 'opening_balance_date'];

    protected function casts(): array
    {
        return [
            'opening_balance_cents' => 'integer',
            'opening_balance_date' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Space, $this> */
    public function space(): BelongsTo
    {
        return $this->belongsTo(Space::class);
    }

    /** @return HasMany<AccountMovement, $this> */
    public function movements(): HasMany
    {
        return $this->hasMany(AccountMovement::class);
    }

    /**
     * Saldo efetivado: marco inicial mais movimentações. Previsões não entram.
     * A soma é feita em NUMERIC pelo PostgreSQL e validada contra o limite.
     */
    public function balanceCents(): int
    {
        $sum = array_key_exists('movements_sum_amount_cents', $this->attributes)
            ? $this->attributes['movements_sum_amount_cents']
            : $this->movements()->sum('amount_cents');

        return $this->opening_balance_cents + (int) ($sum ?? 0);
    }
}
