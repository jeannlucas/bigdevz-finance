<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Agreement extends Model
{
    protected $fillable = [
        'description',
        'total_cents',
        'installment_count',
        'first_due_date',
        'category_id',
        'edited_at',
        'cancelled_at',
        'cancel_reason',
    ];

    protected function casts(): array
    {
        return [
            'total_cents' => 'integer',
            'installment_count' => 'integer',
            'first_due_date' => 'date:Y-m-d',
            'category_id' => 'integer',
            'edited_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    public function isCancelled(): bool
    {
        return $this->cancelled_at !== null;
    }

    public function receivedCents(): int
    {
        return (int) $this->installments()->sum('received_cents');
    }

    /** @return BelongsTo<Space, $this> */
    public function space(): BelongsTo
    {
        return $this->belongsTo(Space::class);
    }

    /** @return BelongsTo<Category, $this> */
    public function category(): BelongsTo
    {
        return $this->belongsTo(Category::class);
    }

    /** @return HasMany<Installment, $this> */
    public function installments(): HasMany
    {
        return $this->hasMany(Installment::class)->orderBy('number');
    }
}
