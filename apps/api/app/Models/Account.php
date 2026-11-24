<?php

namespace App\Models;

use App\Models\Concerns\NormalizesFinancialText;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Facades\DB;

class Account extends Model
{
    use NormalizesFinancialText;

    protected $fillable = ['name', 'bank_id', 'opening_balance_cents', 'opening_balance_date'];

    protected function casts(): array
    {
        return [
            'opening_balance_cents' => 'integer',
            'opening_balance_date' => 'date:Y-m-d',
            'archived_at' => 'datetime',
        ];
    }

    protected function name(): Attribute
    {
        return self::uppercaseTextAttribute();
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

    /** @return HasMany<WiseCurrency, $this> */
    public function wiseCurrencies(): HasMany
    {
        return $this->hasMany(WiseCurrency::class)->select('wise_currencies.*')
            ->selectSub(
                DB::table('wise_currency_movements')->selectRaw('COALESCE(SUM(units), 0)')
                    ->whereColumn('wise_currency_id', 'wise_currencies.id'),
                'movement_units',
            )->orderBy('currency');
    }

    /** @return HasMany<AccountOpeningAdjustment, $this> */
    public function openingAdjustments(): HasMany
    {
        return $this->hasMany(AccountOpeningAdjustment::class)->orderByDesc('id');
    }

    /** Arquivada: fica no histórico e nos totais, mas não recebe operações novas. */
    public function isArchived(): bool
    {
        return $this->archived_at !== null;
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
