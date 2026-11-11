<?php

namespace App\Models;

use App\Models\Concerns\NormalizesFinancialText;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Despesa mensal de valor fixo; as ocorrências são obrigações por ciclo. */
class Recurrence extends Model
{
    use NormalizesFinancialText;

    protected $fillable = ['space_id', 'description', 'payee', 'amount_cents', 'start_date', 'reference_day', 'end_date', 'initial_until', 'category_id'];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'reference_day' => 'integer',
            'start_date' => 'date:Y-m-d',
            'end_date' => 'date:Y-m-d',
            'initial_until' => 'date:Y-m-d',
            'category_id' => 'integer',
        ];
    }

    protected function description(): Attribute
    {
        return self::uppercaseTextAttribute();
    }

    protected function payee(): Attribute
    {
        return self::uppercaseTextAttribute();
    }

    /** @return BelongsTo<Category, $this> */
    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    /** @return HasMany<Payable, $this> */
    public function occurrences(): HasMany
    {
        return $this->hasMany(Payable::class)->orderBy('cycle');
    }
}
