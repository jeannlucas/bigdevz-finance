<?php

namespace App\Actions\Payables;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\PaymentReversal;
use App\Models\Space;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Estorna um pagamento (compensação positiva na conta original, na data do
 * pagamento, reabrindo o restante) e, na correção, cria o substituto na mesma
 * transação. O original fica. Estorno pode sair de conta arquivada; o
 * substituto só entra em conta ativa. Locks: chave, obrigação, pagamento,
 * contas por id crescente.
 */
class ReversePayment
{
    public function __construct(private readonly IdempotentOperations $keys) {}

    /** @param array{account_id: mixed, amount: mixed, paid_on: mixed}|null $replacement */
    public static function fingerprint(int $paymentId, mixed $reason, ?array $replacement): string
    {
        return $replacement === null
            ? IdempotentOperations::fingerprint(IdempotentOperations::PAYMENT_REVERSAL, $paymentId, ['reason' => $reason])
            : IdempotentOperations::fingerprint(IdempotentOperations::PAYMENT_CORRECTION, $paymentId, [
                'reason' => $reason, 'account_id' => $replacement['account_id'],
                'amount' => $replacement['amount'], 'paid_on' => $replacement['paid_on'],
            ]);
    }

    /** @param array{account_id: int, amount_cents: int, paid_on: string}|null $replacement */
    public function handle(User $user, Space $space, int $paymentId, string $reason, string $key, ?array $replacement = null): KeyedResult
    {
        $operation = $replacement === null ? IdempotentOperations::PAYMENT_REVERSAL : IdempotentOperations::PAYMENT_CORRECTION;
        $fingerprint = self::fingerprint($paymentId, $reason, $replacement === null ? null : [
            'account_id' => $replacement['account_id'], 'amount' => Money::fromCents($replacement['amount_cents']), 'paid_on' => $replacement['paid_on'],
        ]);

        return $this->keys->run($user, $space, $key, $operation, $fingerprint, function () use ($user, $space, $paymentId, $reason, $replacement) {
            $payableId = Payment::query()->where('space_id', $space->id)->findOrFail($paymentId)->payable_id;
            $payable = Payable::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($payableId);
            $original = Payment::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($paymentId);
            if (PaymentReversal::query()->where('payment_id', $original->id)->exists()) {
                throw ValidationException::withMessages([
                    'payment' => 'Este pagamento já foi estornado. Para ajustar, use o pagamento substituto, se houver.',
                ]);
            }
            $accounts = Account::query()->where('space_id', $space->id)
                ->whereIn('id', array_values(array_unique(array_filter([$original->account_id, $replacement['account_id'] ?? null]))))
                ->orderBy('id')->lockForUpdate()->get()->keyBy('id');

            if ($replacement !== null) {
                if ($replacement['account_id'] === $original->account_id
                    && $replacement['amount_cents'] === $original->amount_cents
                    && $replacement['paid_on'] === $original->paid_on->toDateString()) {
                    throw ValidationException::withMessages(['payment' => 'Nada a corrigir: altere a conta, o valor ou a data.']);
                }
                $target = $accounts->get($replacement['account_id']);
                $relief = $target?->id === $original->account_id ? $original->amount_cents : 0;
                PayPayable::validateTarget($payable, $target, $replacement['amount_cents'], $replacement['paid_on'],
                    $payable->remainingCents() + $original->amount_cents, $relief);
            }

            $reversal = PaymentReversal::create([
                'space_id' => $space->id, 'payable_id' => $payable->id, 'payment_id' => $original->id,
                'account_id' => $original->account_id, 'user_id' => $user->id, 'reason' => $reason,
            ]);
            AccountMovement::create([
                'account_id' => $original->account_id, 'payment_reversal_id' => $reversal->id,
                'amount_cents' => $original->amount_cents, 'effective_date' => $original->paid_on->toDateString(),
            ]);
            $payable->decrement('paid_cents', $original->amount_cents);

            if ($replacement !== null) {
                $substitute = Payment::create([
                    'space_id' => $space->id, 'payable_id' => $payable->id, 'account_id' => $replacement['account_id'],
                    'user_id' => $user->id, 'amount_cents' => $replacement['amount_cents'], 'paid_on' => $replacement['paid_on'],
                ]);
                AccountMovement::create([
                    'account_id' => $substitute->account_id, 'payment_id' => $substitute->id,
                    'amount_cents' => -$substitute->amount_cents, 'effective_date' => $replacement['paid_on'],
                ]);
                $payable->increment('paid_cents', $substitute->amount_cents);
                $reversal->update(['replacement_payment_id' => $substitute->id]);
            }

            return ['payment_reversal_id' => $reversal->id];
        });
    }
}
