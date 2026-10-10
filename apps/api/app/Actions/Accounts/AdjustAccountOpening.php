<?php

namespace App\Actions\Accounts;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\AccountOpeningAdjustment;
use App\Models\Space;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Corrige o saldo inicial e/ou a data de abertura de uma conta, com trilha.
 *
 * O saldo é sempre abertura + movimentações, sem filtro de data: a correção
 * muda o saldo exatamente pela diferença entre a abertura antiga e a nova e
 * não cria movimentação (nem receita nem despesa). Movimentações nunca são
 * alteradas. A nova data não pode ficar depois da primeira movimentação, para
 * nenhum recebimento ou compensação existente ficar antes da abertura.
 *
 * A conta é travada (FOR UPDATE), como em recebimentos e estornos, que travam
 * a conta antes de gravar movimentações: a validação usa dados atuais.
 */
class AdjustAccountOpening
{
    public function __construct(private readonly IdempotentOperations $keys) {}

    public static function fingerprint(int $accountId, mixed $openingBalance, mixed $openingDate, mixed $reason): string
    {
        return IdempotentOperations::fingerprint(IdempotentOperations::OPENING_ADJUSTMENT, $accountId, [
            'opening_balance' => $openingBalance, 'opening_balance_date' => $openingDate, 'reason' => $reason,
        ]);
    }

    public function handle(User $user, Space $space, int $accountId, int $openingCents, string $openingDate, string $reason, string $idempotencyKey): KeyedResult
    {
        $fingerprint = self::fingerprint($accountId, Money::fromCents($openingCents), $openingDate, $reason);

        return $this->keys->run($user, $space, $idempotencyKey, IdempotentOperations::OPENING_ADJUSTMENT, $fingerprint, function () use ($user, $space, $accountId, $openingCents, $openingDate, $reason) {
            $account = Account::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($accountId);
            $previousDate = $account->opening_balance_date->toDateString();

            if ($openingCents === $account->opening_balance_cents && $openingDate === $previousDate) {
                throw ValidationException::withMessages(['opening_balance' => 'Nada a corrigir: altere o saldo inicial ou a data de abertura.']);
            }
            $firstMovement = $account->movements()->min('effective_date');
            if ($firstMovement !== null && $openingDate > $firstMovement) {
                throw ValidationException::withMessages([
                    'opening_balance_date' => 'A abertura não pode ficar depois da primeira movimentação da conta ('
                        .date('d/m/Y', strtotime($firstMovement)).'): recebimentos e estornos existentes ficariam antes dela.',
                ]);
            }
            $movements = $account->balanceCents() - $account->opening_balance_cents;
            if ($openingCents + $movements > Money::MAX_CENTS) {
                throw ValidationException::withMessages(['opening_balance' => 'O saldo da conta ultrapassaria o limite suportado.']);
            }

            $adjustment = AccountOpeningAdjustment::create([
                'space_id' => $space->id,
                'account_id' => $account->id,
                'user_id' => $user->id,
                'reason' => $reason,
                'previous_opening_balance_cents' => $account->opening_balance_cents,
                'previous_opening_balance_date' => $previousDate,
                'new_opening_balance_cents' => $openingCents,
                'new_opening_balance_date' => $openingDate,
            ]);
            $account->update(['opening_balance_cents' => $openingCents, 'opening_balance_date' => $openingDate]);

            return ['account_opening_adjustment_id' => $adjustment->id];
        });
    }
}
