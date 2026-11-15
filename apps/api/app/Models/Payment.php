<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

/** Pagamento de uma obrigação: saída de uma conta do mesmo espaço. */
class Payment extends Model
{
    protected $fillable = [
        'space_id', 'payable_id', 'account_id', 'user_id',
        'amount_cents', 'principal_cents', 'interest_cents', 'fine_cents', 'discount_cents', 'total_cents',
        'paid_on',
    ];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'principal_cents' => 'integer',
            'interest_cents' => 'integer',
            'fine_cents' => 'integer',
            'discount_cents' => 'integer',
            'total_cents' => 'integer',
            'paid_on' => 'date:Y-m-d',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Payment $payment): void {
            if ($payment->principal_cents === null && $payment->amount_cents !== null) {
                $payment->principal_cents = $payment->amount_cents;
            }
            if ($payment->interest_cents === null) {
                $payment->interest_cents = 0;
            }
            if ($payment->fine_cents === null) {
                $payment->fine_cents = 0;
            }
            if ($payment->discount_cents === null) {
                $payment->discount_cents = 0;
            }
            if ($payment->total_cents === null && $payment->principal_cents !== null) {
                $payment->total_cents = $payment->principal_cents
                    + $payment->interest_cents
                    + $payment->fine_cents
                    - $payment->discount_cents;
            }
        });
    }

    /** @return BelongsTo<Payable, $this> */
    public function payable(): BelongsTo
    {
        return $this->belongsTo(Payable::class);
    }

    /** @return HasOne<PaymentReversal, $this> */
    public function reversal(): HasOne
    {
        return $this->hasOne(PaymentReversal::class);
    }

    /** @return HasOne<PaymentReversal, $this> */
    public function correctionOf(): HasOne
    {
        return $this->hasOne(PaymentReversal::class, 'replacement_payment_id');
    }

    /** @return HasOne<AccountMovement, $this> */
    public function movement(): HasOne
    {
        return $this->hasOne(AccountMovement::class);
    }
}
