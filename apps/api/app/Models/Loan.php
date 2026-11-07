<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Loan extends Model
{
    public const KIND_TAKEN = 'taken';

    public const KIND_GRANTED = 'granted';

    public const STATUS_ACTIVE = 'active';

    public const STATUS_SETTLED = 'settled';

    public const STATUS_CANCELLED = 'cancelled';

    protected $fillable = [
        'space_id',
        'user_id',
        'kind',
        'title',
        'counterparty',
        'principal_cents',
        'total_cents',
        'installment_count',
        'first_due_date',
        'disbursement_account_id',
        'disbursed_at',
        'status',
        'notes',
        'payable_plan_id',
        'agreement_id',
    ];

    protected function casts(): array
    {
        return [
            'principal_cents' => 'integer',
            'total_cents' => 'integer',
            'installment_count' => 'integer',
            'first_due_date' => 'date:Y-m-d',
            'disbursed_at' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Space, $this> */
    public function space(): BelongsTo
    {
        return $this->belongsTo(Space::class);
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return BelongsTo<Account, $this> */
    public function disbursementAccount(): BelongsTo
    {
        return $this->belongsTo(Account::class, 'disbursement_account_id');
    }

    /** @return BelongsTo<PayablePlan, $this> */
    public function payablePlan(): BelongsTo
    {
        return $this->belongsTo(PayablePlan::class, 'payable_plan_id');
    }

    /** @return BelongsTo<Agreement, $this> */
    public function agreement(): BelongsTo
    {
        return $this->belongsTo(Agreement::class, 'agreement_id');
    }

    /** @return HasOne<AccountMovement, $this> */
    public function disbursementMovement(): HasOne
    {
        return $this->hasOne(AccountMovement::class, 'loan_disbursement_id');
    }

    public function isTaken(): bool
    {
        return $this->kind === self::KIND_TAKEN;
    }

    public function isGranted(): bool
    {
        return $this->kind === self::KIND_GRANTED;
    }

    public function interestCents(): int
    {
        return $this->total_cents - $this->principal_cents;
    }

    public function paidOrReceivedCents(): int
    {
        if ($this->isTaken()) {
            if ($this->relationLoaded('payablePlan') && $this->payablePlan?->relationLoaded('payables')) {
                return (int) $this->payablePlan->payables->sum('paid_cents');
            }

            return (int) ($this->payablePlan?->payables()->sum('paid_cents') ?? 0);
        }

        if ($this->relationLoaded('agreement') && $this->agreement?->relationLoaded('installments')) {
            return (int) $this->agreement->installments->sum('received_cents');
        }

        return (int) ($this->agreement?->installments()->sum('received_cents') ?? 0);
    }

    public function remainingCents(): int
    {
        $remaining = $this->total_cents - $this->paidOrReceivedCents();

        return max(0, $remaining);
    }

    public function computedStatus(): string
    {
        if ($this->status === self::STATUS_CANCELLED) {
            return self::STATUS_CANCELLED;
        }

        if ($this->remainingCents() === 0) {
            return self::STATUS_SETTLED;
        }

        return self::STATUS_ACTIVE;
    }
}
