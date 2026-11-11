<?php

namespace App\Models;

use App\Models\Concerns\NormalizesFinancialText;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Cartão: só nome e dia de vencimento. Não é conta e não tem saldo. */
class Card extends Model
{
    use NormalizesFinancialText;

    protected $fillable = ['space_id', 'name', 'due_day', 'first_cycle'];

    protected function casts(): array
    {
        return ['due_day' => 'integer', 'first_cycle' => 'date:Y-m-d', 'archived_at' => 'datetime'];
    }

    protected function name(): Attribute
    {
        return self::uppercaseTextAttribute();
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
