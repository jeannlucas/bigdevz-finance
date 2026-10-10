<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasOne;

/**
 * Estorno de um recebimento: desfaz seu efeito com uma movimentação
 * compensatória, sem apagar nem alterar o original. Com substituto, é uma
 * correção. Cada recebimento é estornado no máximo uma vez (UNIQUE no banco).
 */
class ReceiptReversal extends Model
{
    protected $fillable = [
        'space_id', 'installment_id', 'receipt_id', 'account_id',
        'replacement_receipt_id', 'user_id', 'reason',
    ];

    /** @return BelongsTo<Receipt, $this> */
    public function receipt(): BelongsTo
    {
        return $this->belongsTo(Receipt::class);
    }

    /** @return BelongsTo<Receipt, $this> */
    public function replacement(): BelongsTo
    {
        return $this->belongsTo(Receipt::class, 'replacement_receipt_id');
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return HasOne<AccountMovement, $this> */
    public function movement(): HasOne
    {
        return $this->hasOne(AccountMovement::class);
    }

    public function isCorrection(): bool
    {
        return $this->replacement_receipt_id !== null;
    }
}
