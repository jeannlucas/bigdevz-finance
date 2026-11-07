<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Despesa mensal de valor fixo; as ocorrências são obrigações por ciclo. */
class Recurrence extends Model
{
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
