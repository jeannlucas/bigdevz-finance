<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Obrigação a pagar. Não movimenta conta; só pagamentos movimentam.
 * paid_cents é o pago líquido (pagamentos menos estornos).
 */
class Payable extends Model
{
    public const SINGLE = 'single';

    public const INSTALLMENT = 'installment';

    public const RECURRING = 'recurring';

    public const CARD_BILL = 'card_bill';

    protected $fillable = [
        'space_id', 'kind', 'description', 'payee', 'amount_cents', 'paid_cents', 'due_date',
        'plan_id', 'installment_number', 'recurrence_id', 'card_id', 'cycle',
    ];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'paid_cents' => 'integer',
            'installment_number' => 'integer',
            'due_date' => 'date:Y-m-d',
            'cycle' => 'date:Y-m-d',
            'edited_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    /** @return BelongsTo<PayablePlan, $this> */
    public function plan(): BelongsTo
    {
        return $this->belongsTo(PayablePlan::class, 'plan_id');
    }

    /** @return BelongsTo<Card, $this> */
    public function card(): BelongsTo
    {
        return $this->belongsTo(Card::class);
    }

    /** @return HasMany<Payment, $this> */
    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class)->orderBy('paid_on')->orderBy('id');
    }

    /** Restante; nulo enquanto a fatura não tem total informado. */
    public function remainingCents(): ?int
    {
        return $this->amount_cents === null ? null : $this->amount_cents - $this->paid_cents;
    }

    public function isCancelled(): bool
    {
        return $this->cancelled_at !== null;
    }

    public function status(): string
    {
        return match (true) {
            $this->isCancelled() => 'cancelled',
            $this->amount_cents === null => 'awaiting_amount',
            $this->paid_cents === $this->amount_cents => 'paid',
            $this->paid_cents > 0 => 'partial',
            default => 'open',
        };
    }

    /** Vencida: tem restante e o vencimento passou no fuso do produto. Coexiste com parcial. */
    public function isOverdue(): bool
    {
        return ! $this->isCancelled()
            && ($this->remainingCents() ?? 0) > 0
            && $this->due_date->toDateString() < now(config('finance.timezone'))->toDateString();
    }
}
