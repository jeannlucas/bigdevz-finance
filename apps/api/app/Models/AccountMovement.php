<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Movimentação efetivada da conta: entrada de recebimento, saída de
 * pagamento, transferência entre contas, ou compensação de estorno.
 */
class AccountMovement extends Model
{
    protected $fillable = [
        'account_id',
        'receipt_id',
        'receipt_reversal_id',
        'payment_id',
        'payment_reversal_id',
        'transfer_id',
        'loan_disbursement_id',
        'amount_cents',
        'effective_date',
    ];

    protected function casts(): array
    {
        return [
            'amount_cents' => 'integer',
            'effective_date' => 'date:Y-m-d',
        ];
    }

    /** @return BelongsTo<Account, $this> */
    public function account(): BelongsTo
    {
        return $this->belongsTo(Account::class);
    }

    /** @return BelongsTo<Receipt, $this> */
    public function receipt(): BelongsTo
    {
        return $this->belongsTo(Receipt::class);
    }

    /** @return BelongsTo<ReceiptReversal, $this> */
    public function receiptReversal(): BelongsTo
    {
        return $this->belongsTo(ReceiptReversal::class);
    }

    /** @return BelongsTo<Payment, $this> */
    public function payment(): BelongsTo
    {
        return $this->belongsTo(Payment::class);
    }

    /** @return BelongsTo<PaymentReversal, $this> */
    public function paymentReversal(): BelongsTo
    {
        return $this->belongsTo(PaymentReversal::class);
    }

    /** @return BelongsTo<Transfer, $this> */
    public function transfer(): BelongsTo
    {
        return $this->belongsTo(Transfer::class);
    }

    /** @return BelongsTo<Loan, $this> */
    public function loanDisbursement(): BelongsTo
    {
        return $this->belongsTo(Loan::class, 'loan_disbursement_id');
    }

    public function isCredit(): bool
    {
        return $this->amount_cents > 0;
    }

    public function isDebit(): bool
    {
        return $this->amount_cents < 0;
    }
}
