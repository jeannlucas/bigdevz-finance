<?php

namespace App\Models;

use App\Models\Concerns\NormalizesFinancialText;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Agreement extends Model
{
    use NormalizesFinancialText;

    protected $fillable = [
        'kind',
        'is_variable',
        'description',
        'amount_cents',
        'estimated_amount_cents',
        'total_cents',
        'installment_count',
        'first_due_date',
        'start_date',
        'reference_day',
        'end_date',
        'initial_until',
        'category_id',
        'edited_at',
        'cancelled_at',
        'cancel_reason',
        'idempotency_key',
    ];

    protected function casts(): array
    {
        return [
            'kind' => 'string',
            'is_variable' => 'boolean',
            'amount_cents' => 'integer',
            'estimated_amount_cents' => 'integer',
            'total_cents' => 'integer',
            'installment_count' => 'integer',
            'first_due_date' => 'date:Y-m-d',
            'start_date' => 'date:Y-m-d',
            'reference_day' => 'integer',
            'end_date' => 'date:Y-m-d',
            'initial_until' => 'date:Y-m-d',
            'category_id' => 'integer',
            'edited_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    public function isRecurring(): bool
    {
        return $this->kind === 'recurring';
    }

    protected function description(): Attribute
    {
        return self::uppercaseTextAttribute();
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
