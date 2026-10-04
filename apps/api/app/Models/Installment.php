<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Installment extends Model
{
    public const PENDING = 'pending';

    public const PARTIAL = 'partial';

    public const PAID = 'paid';

    protected $fillable = ['space_id', 'number', 'amount_cents', 'received_cents', 'due_date'];

    protected function casts(): array
    {
        return [
            'number' => 'integer',
            'amount_cents' => 'integer',
            'received_cents' => 'integer',
            'due_date' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Agreement, $this> */
    public function agreement(): BelongsTo
    {
        return $this->belongsTo(Agreement::class);
    }

    /** @return HasMany<Receipt, $this> */
    public function receipts(): HasMany
    {
        return $this->hasMany(Receipt::class)->orderBy('received_on')->orderBy('id');
    }

    public function remainingCents(): int
    {
        return $this->amount_cents - $this->received_cents;
    }

    public function status(): string
    {
        return match (true) {
            $this->received_cents === $this->amount_cents => self::PAID,
            $this->received_cents > 0 => self::PARTIAL,
            default => self::PENDING,
        };
    }

    /** Vencida: há saldo pendente e o vencimento já passou no fuso do produto. */
    public function isOverdue(): bool
    {
        return $this->remainingCents() > 0
            && $this->due_date->toDateString() < now(config('finance.timezone'))->toDateString();
    }
}
