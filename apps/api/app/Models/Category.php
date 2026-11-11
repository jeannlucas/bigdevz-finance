<?php

namespace App\Models;

use App\Models\Concerns\NormalizesFinancialText;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Category extends Model
{
    use NormalizesFinancialText;

    public const TYPE_INCOME = 'income';

    public const TYPE_EXPENSE = 'expense';

    protected $fillable = [
        'space_id',
        'name',
        'icon',
        'color',
        'type',
        'is_default',
    ];

    protected $casts = [
        'is_default' => 'boolean',
    ];

    protected function name(): Attribute
    {
        return self::uppercaseTextAttribute();
    }

    /** @return BelongsTo<Space, $this> */
    public function space(): BelongsTo
    {
        return $this->belongsTo(Space::class);
    }

    /** @return HasMany<Agreement, $this> */
    public function agreements(): HasMany
    {
        return $this->hasMany(Agreement::class);
    }

    /** @return HasMany<Payable, $this> */
    public function payables(): HasMany
    {
        return $this->hasMany(Payable::class);
    }

    /** @return HasMany<AccountMovement, $this> */
    public function accountMovements(): HasMany
    {
        return $this->hasMany(AccountMovement::class);
    }
}
