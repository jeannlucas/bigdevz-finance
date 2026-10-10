<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasOne;

/** Estorno (ou correção, com substituto) de um pagamento. O original fica. */
class PaymentReversal extends Model
{
    protected $fillable = ['space_id', 'payable_id', 'payment_id', 'account_id', 'replacement_payment_id', 'user_id', 'reason'];

    /** @return HasOne<AccountMovement, $this> */
    public function movement(): HasOne
    {
        return $this->hasOne(AccountMovement::class);
    }

    public function isCorrection(): bool
    {
        return $this->replacement_payment_id !== null;
    }
}
