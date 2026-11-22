<?php

namespace App\Actions\Payables;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\ObligationChange;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\Space;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Registra uma despesa paga à vista (compra no débito):
 * Cria a obrigação quitada, o pagamento debitando a conta e o movimento de saída
 * atomicamente na mesma transação, protegido por Idempotency-Key.
 */
class RegisterDirectExpense
{
    public function __construct(private readonly IdempotentOperations $keys) {}

    /** @param array<string, mixed> $data */
    public static function fingerprint(Space $space, array $data): string
    {
        ksort($data);

        return IdempotentOperations::fingerprint(IdempotentOperations::PAYABLE, $space->id, $data);
    }

    /**
     * @param array{
     *     account_id: int,
     *     amount: string,
     *     paid_on: string,
     *     description: string,
     *     payee?: ?string,
     *     category_id?: ?int
     * } $data
     */
    public function handle(User $user, Space $space, array $data, string $key, string $fingerprint): KeyedResult
    {
        return $this->keys->run($user, $space, $key, IdempotentOperations::PAYABLE, $fingerprint, function () use ($user, $space, $data) {
            $space->ensureDateNotClosed($data['paid_on'], 'registro de despesa paga');

            $account = Account::query()->where('space_id', $space->id)->lockForUpdate()->find($data['account_id']);
            if (! $account) {
                throw ValidationException::withMessages(['account_id' => 'Conta bancária não encontrada no espaço.']);
            }
            if ($account->isArchived()) {
                throw ValidationException::withMessages(['account_id' => 'Esta conta está arquivada. Escolha uma conta ativa.']);
            }
            if ($data['paid_on'] < $account->opening_balance_date->toDateString()) {
                throw ValidationException::withMessages([
                    'paid_on' => 'A data do pagamento não pode ser anterior ao saldo inicial da conta ('.$account->opening_balance_date->format('d/m/Y').').',
                ]);
            }

            $categoryId = isset($data['category_id']) ? (int) $data['category_id'] : null;
            if ($categoryId !== null) {
                $space->categories()->where('type', 'expense')->findOrFail($categoryId);
            }

            $amountCents = Money::toCents($data['amount']);
            if ($amountCents <= 0 || $amountCents > Money::MAX_CENTS) {
                throw ValidationException::withMessages(['amount' => 'Valor inválido.']);
            }

            if ($account->balanceCents() - $amountCents < -Money::MAX_CENTS) {
                throw ValidationException::withMessages(['amount' => 'O saldo da conta ultrapassaria o limite suportado.']);
            }

            $payable = Payable::create([
                'space_id' => $space->id,
                'kind' => Payable::SINGLE,
                'is_direct_expense' => true,
                'description' => $data['description'],
                'payee' => $data['payee'] ?? null,
                'amount_cents' => $amountCents,
                'paid_cents' => $amountCents,
                'due_date' => $data['paid_on'],
                'category_id' => $categoryId,
            ]);

            $payment = Payment::create([
                'space_id' => $space->id,
                'payable_id' => $payable->id,
                'account_id' => $account->id,
                'user_id' => $user->id,
                'amount_cents' => $amountCents,
                'principal_cents' => $amountCents,
                'interest_cents' => 0,
                'fine_cents' => 0,
                'discount_cents' => 0,
                'total_cents' => $amountCents,
                'paid_on' => $data['paid_on'],
            ]);

            AccountMovement::create([
                'account_id' => $account->id,
                'payment_id' => $payment->id,
                'category_id' => $categoryId,
                'amount_cents' => -$amountCents,
                'effective_date' => $data['paid_on'],
            ]);

            ObligationChange::create([
                'space_id' => $space->id,
                'user_id' => $user->id,
                'subject' => 'payable',
                'subject_id' => $payable->id,
                'action' => 'direct_expense',
                'before' => [],
                'after' => [
                    'payable_id' => $payable->id,
                    'account_id' => $account->id,
                    'amount_cents' => $amountCents,
                    'paid_on' => $data['paid_on'],
                    'category_id' => $categoryId,
                ],
                'reason' => 'Compra no débito / Despesa paga à vista',
            ]);

            return ['payable_id' => $payable->id];
        });
    }
}
