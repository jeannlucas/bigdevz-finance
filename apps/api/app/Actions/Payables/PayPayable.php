<?php

namespace App\Actions\Payables;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\AccountMovement;
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

    public static function fingerprint(int $payableId, mixed $accountId, mixed $amount, mixed $paidOn): string
    {
        return IdempotentOperations::fingerprint(IdempotentOperations::PAYMENT, $payableId, [
            'account_id' => $accountId, 'amount' => $amount, 'paid_on' => $paidOn,
        ]);
    }

    public function handle(User $user, Space $space, int $payableId, int $accountId, int $amountCents, string $paidOn, string $key): KeyedResult
    {
        $fingerprint = self::fingerprint($payableId, $accountId, Money::fromCents($amountCents), $paidOn);

        return $this->keys->run($user, $space, $key, IdempotentOperations::PAYMENT, $fingerprint, function () use ($user, $space, $payableId, $accountId, $amountCents, $paidOn) {
            $payable = Payable::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($payableId);
            $account = Account::query()->where('space_id', $space->id)->lockForUpdate()->find($accountId);
            self::validateTarget($payable, $account, $amountCents, $paidOn, $payable->remainingCents() ?? 0);

            $payment = Payment::create([
                'space_id' => $space->id, 'payable_id' => $payable->id, 'account_id' => $account->id,
                'user_id' => $user->id, 'amount_cents' => $amountCents, 'paid_on' => $paidOn,
            ]);
            AccountMovement::create([
                'account_id' => $account->id, 'payment_id' => $payment->id,
                'amount_cents' => -$amountCents, 'effective_date' => $paidOn,
            ]);
            $payable->increment('paid_cents', $amountCents);

            return ['payment_id' => $payment->id];
        });
    }

    /** Regras de destino de um pagamento novo ou substituto. */
    public static function validateTarget(Payable $payable, ?Account $account, int $amountCents, string $paidOn, int $available, int $balanceRelief = 0): void
    {
        if ($payable->isCancelled()) {
            throw ValidationException::withMessages(['payable' => 'Obrigação cancelada não recebe pagamento.']);
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
            throw ValidationException::withMessages(['amount' => 'O valor excede o restante da obrigação ('.Money::fromCents($available).').']);
        }
        if ($account->balanceCents() + $balanceRelief - $amountCents < -Money::MAX_CENTS) {
            throw ValidationException::withMessages(['amount' => 'O saldo da conta ultrapassaria o limite suportado.']);
        }
    }
}
