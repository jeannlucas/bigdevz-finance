<?php

namespace App\Models;

use App\Models\Concerns\NormalizesFinancialText;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Despesa parcelada: as parcelas são obrigações geradas de uma vez. */
class PayablePlan extends Model
{
    use NormalizesFinancialText;

    protected $fillable = ['space_id', 'description', 'payee', 'total_cents', 'installment_count', 'first_due_date', 'category_id'];

    protected function casts(): array
    {
        return ['total_cents' => 'integer', 'installment_count' => 'integer', 'first_due_date' => 'date:Y-m-d', 'category_id' => 'integer'];
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
    public function payables(): HasMany
    {
        return $this->hasMany(Payable::class, 'plan_id')->orderBy('installment_number');
    }
}
