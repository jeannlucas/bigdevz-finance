<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Cartão: só nome e dia de vencimento. Não é conta e não tem saldo. */
class Card extends Model
{
    protected $fillable = ['space_id', 'name', 'due_day', 'first_cycle'];

    protected function casts(): array
    {
        return ['due_day' => 'integer', 'first_cycle' => 'date:Y-m-d', 'archived_at' => 'datetime'];
    }

    /** @return HasMany<Payable, $this> */
    public function bills(): HasMany
    {
        return $this->hasMany(Payable::class)->orderBy('cycle');
    }

    public function isArchived(): bool
    {
        return $this->archived_at !== null;
    }
}
