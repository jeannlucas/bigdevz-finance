<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Despesa parcelada: as parcelas são obrigações geradas de uma vez. */
class PayablePlan extends Model
{
    protected $fillable = ['space_id', 'description', 'payee', 'total_cents', 'installment_count', 'first_due_date'];

    protected function casts(): array
    {
        return ['total_cents' => 'integer', 'installment_count' => 'integer', 'first_due_date' => 'date:Y-m-d'];
    }

    /** @return HasMany<Payable, $this> */
    public function payables(): HasMany
    {
        return $this->hasMany(Payable::class, 'plan_id')->orderBy('installment_number');
    }
}
