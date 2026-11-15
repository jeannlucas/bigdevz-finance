<?php

namespace App\Actions\Payables;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\Money;
use App\Domain\Receivables\PaymentSettlement;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\ObligationChange;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\Space;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Registra um pagamento total ou parcial: pagamento, saída na conta e pago
 * líquido da obrigação na mesma transação. Trava a obrigação e depois a
 * conta (mesma ordem de recebimentos: chave, documento, conta), então
 * pagamentos simultâneos não excedem o restante nem perdem atualização de
 * saldo. Sem limite de saldo: a conta pode ficar negativa (decisão 0006).
 */
class PayPayable
{
    public function __construct(private readonly IdempotentOperations $keys) {}

    public static function fingerprint(
        int $payableId,
        mixed $accountId,
        mixed $amount,
        mixed $paidOn,
        mixed $interest = null,
        mixed $fine = null,
        mixed $discount = null
    ): string {
        $payload = [
            'account_id' => $accountId,
            'amount' => $amount,
            'paid_on' => $paidOn,
        ];
        if ($interest !== null) {
            $payload['interest_amount'] = $interest;
        }
        if ($fine !== null) {
            $payload['fine_amount'] = $fine;
        }
        if ($discount !== null) {
            $payload['discount_amount'] = $discount;
        }

        return IdempotentOperations::fingerprint(IdempotentOperations::PAYMENT, $payableId, $payload);
    }

    public function handle(
        User $user,
        Space $space,
        int $payableId,
        int $accountId,
        int $amountCents,
        string $paidOn,
        string $key,
        int $interestCents = 0,
        int $fineCents = 0,
        int $discountCents = 0
    ): KeyedResult {
        $settlement = PaymentSettlement::calculate($amountCents, $interestCents, $fineCents, $discountCents);
        $fingerprint = self::fingerprint(
            $payableId,
            $accountId,
            Money::fromCents($amountCents),
            $paidOn,
            $interestCents > 0 ? Money::fromCents($interestCents) : null,
            $fineCents > 0 ? Money::fromCents($fineCents) : null,
            $discountCents > 0 ? Money::fromCents($discountCents) : null
        );

        return $this->keys->run($user, $space, $key, IdempotentOperations::PAYMENT, $fingerprint, function () use ($user, $space, $payableId, $accountId, $paidOn, $settlement) {
            $payable = Payable::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($payableId);
            $account = Account::query()->where('space_id', $space->id)->lockForUpdate()->find($accountId);
            self::validateTarget(
                $payable,
                $account,
                $settlement['principal_cents'],
                $paidOn,
                $payable->remainingCents() ?? 0,
                0,
                $settlement['total_cents']
            );

            $payment = Payment::create([
                'space_id' => $space->id,
                'payable_id' => $payable->id,
                'account_id' => $account->id,
                'user_id' => $user->id,
                'amount_cents' => $settlement['total_cents'],
                'principal_cents' => $settlement['principal_cents'],
                'interest_cents' => $settlement['interest_cents'],
                'fine_cents' => $settlement['fine_cents'],
                'discount_cents' => $settlement['discount_cents'],
                'total_cents' => $settlement['total_cents'],
                'paid_on' => $paidOn,
            ]);
            $oldPaid = $payable->paid_cents;
            $oldRemaining = $payable->remainingCents();

            AccountMovement::create([
                'account_id' => $account->id,
                'payment_id' => $payment->id,
                'amount_cents' => -$settlement['total_cents'],
                'effective_date' => $paidOn,
            ]);
            $payable->increment('paid_cents', $settlement['principal_cents']);

            ObligationChange::create([
                'space_id' => $space->id,
                'user_id' => $user->id,
                'subject' => 'payment',
                'subject_id' => $payment->id,
                'action' => 'payment',
                'before' => [
                    'payable_id' => $payable->id,
                    'amount_cents' => $payable->amount_cents,
                    'paid_cents' => $oldPaid,
                    'remaining_cents' => $oldRemaining,
                ],
                'after' => [
                    'payable_id' => $payable->id,
                    'amount_cents' => $payable->amount_cents,
                    'paid_cents' => $oldPaid + $settlement['principal_cents'],
                    'remaining_cents' => $oldRemaining !== null ? $oldRemaining - $settlement['principal_cents'] : null,
                    'payment_id' => $payment->id,
                    'account_id' => $account->id,
                    'paid_on' => $paidOn,
                    'principal_cents' => $settlement['principal_cents'],
                    'interest_cents' => $settlement['interest_cents'],
                    'fine_cents' => $settlement['fine_cents'],
                    'discount_cents' => $settlement['discount_cents'],
                    'total_cents' => $settlement['total_cents'],
                ],
            ]);

            return ['payment_id' => $payment->id];
        });
    }

    /** Regras de destino de um pagamento novo ou substituto. */
    public static function validateTarget(
        Payable $payable,
        ?Account $account,
        int $amountCents,
        string $paidOn,
        int $available,
        int $balanceRelief = 0,
        ?int $totalCents = null
    ): void {
        $totalCents ??= $amountCents;
        if ($payable->isCancelled()) {
            throw ValidationException::withMessages(['payable' => 'Conta a pagar cancelada não recebe pagamento.']);
        }
        if ($payable->amount_cents === null) {
            throw ValidationException::withMessages(['payable' => 'Informe o total da fatura antes de pagar.']);
        }
        if ($account === null) {
            throw ValidationException::withMessages(['account_id' => 'Selecione uma conta deste espaço.']);
        }
        if ($account->isArchived()) {
            throw ValidationException::withMessages(['account_id' => 'Esta conta está arquivada. Escolha uma conta ativa.']);
        }
        if ($paidOn < $account->opening_balance_date->toDateString()) {
            throw ValidationException::withMessages([
                'paid_on' => 'A data do pagamento não pode ser anterior ao saldo inicial da conta ('.$account->opening_balance_date->format('d/m/Y').').',
            ]);
        }
        if ($amountCents > $available) {
            throw ValidationException::withMessages(['amount' => 'O valor excede o saldo restante da conta a pagar ('.Money::fromCents($available).').']);
        }
        if ($account->balanceCents() + $balanceRelief - $totalCents < -Money::MAX_CENTS) {
            throw ValidationException::withMessages(['amount' => 'O saldo da conta ultrapassaria o limite suportado.']);
        }
    }
}
