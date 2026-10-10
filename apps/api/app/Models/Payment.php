<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

/** Pagamento de uma obrigação: saída de uma conta do mesmo espaço. */
class Payment extends Model
{
    protected $fillable = ['space_id', 'payable_id', 'account_id', 'user_id', 'amount_cents', 'paid_on'];

    protected function casts(): array
    {
        return ['amount_cents' => 'integer', 'paid_on' => 'date:Y-m-d'];
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
