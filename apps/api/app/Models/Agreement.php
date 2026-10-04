<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Agreement extends Model
{
    protected $fillable = ['description', 'total_cents', 'installment_count', 'first_due_date'];

    protected function casts(): array
    {
        return [
            'total_cents' => 'integer',
            'installment_count' => 'integer',
            'first_due_date' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Space, $this> */
    public function space(): BelongsTo
    {
        return $this->belongsTo(Space::class);
    }

    /** @return HasMany<Installment, $this> */
    public function installments(): HasMany
    {
        return $this->hasMany(Installment::class)->orderBy('number');
    }
}
