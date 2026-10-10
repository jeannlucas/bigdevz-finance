<?php

namespace App\Actions\Receivables;

use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Installment;
use App\Models\Receipt;
use App\Models\ReceiptReversal;
use App\Models\Space;
use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Estorna um recebimento e, na correção, registra o substituto na mesma
 * transação. O original e sua movimentação não mudam: o estorno grava uma
 * movimentação compensatória negativa na conta original, com a data do
 * original (o lançamento errado é neutralizado onde ocorreu; nunca antes da
 * abertura da conta, que o original já respeitava). O substituto entra na
 * data informada, que segue as regras de qualquer recebimento.
 *
 * Locks na mesma ordem dos recebimentos: chave, parcela, recebimento e
 * contas por id crescente. Estornar não exige saldo: desfaz uma entrada
 * mesmo que o dinheiro já tenha saído (hoje só há entradas, então o saldo
 * não fica abaixo do saldo inicial).
 */
class ReverseReceipt
{
    public function __construct(private readonly IdempotentOperations $keys) {}

    /** @param array{account_id: mixed, amount: mixed, received_on: mixed}|null $replacement */
    public static function fingerprint(int $receiptId, mixed $reason, ?array $replacement): string
    {
        return $replacement === null
            ? IdempotentOperations::fingerprint(IdempotentOperations::REVERSAL, $receiptId, ['reason' => $reason])
            : IdempotentOperations::fingerprint(IdempotentOperations::CORRECTION, $receiptId, [
                'reason' => $reason,
                'account_id' => $replacement['account_id'],
                'amount' => $replacement['amount'],
                'received_on' => $replacement['received_on'],
            ]);
    }

    /** @param array{account_id: int, amount_cents: int, received_on: string}|null $replacement */
    public function handle(User $user, Space $space, int $receiptId, string $reason, string $idempotencyKey, ?array $replacement = null): KeyedResult
    {
        $operation = $replacement === null ? IdempotentOperations::REVERSAL : IdempotentOperations::CORRECTION;
        $fingerprint = self::fingerprint($receiptId, $reason, $replacement === null ? null : [
            'account_id' => $replacement['account_id'],
            'amount' => Money::fromCents($replacement['amount_cents']),
            'received_on' => $replacement['received_on'],
        ]);

        return $this->keys->run($user, $space, $idempotencyKey, $operation, $fingerprint, function () use ($user, $space, $receiptId, $reason, $replacement) {
            $installmentId = Receipt::query()->where('space_id', $space->id)->findOrFail($receiptId)->installment_id;
            $installment = Installment::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($installmentId);
            $original = Receipt::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($receiptId);

            if (ReceiptReversal::query()->where('receipt_id', $original->id)->exists()) {
                throw ValidationException::withMessages([
                    'receipt' => 'Este recebimento já foi estornado. Para ajustar, use o recebimento substituto, se houver.',
                ]);
            }

            $accountIds = array_values(array_unique(array_filter([$original->account_id, $replacement['account_id'] ?? null])));
            $accounts = Account::query()->where('space_id', $space->id)->whereIn('id', $accountIds)
                ->orderBy('id')->lockForUpdate()->get()->keyBy('id');

            if ($replacement !== null) {
                $this->validateReplacement($installment, $original, $accounts->get($replacement['account_id']), $replacement);
            }

            $reversal = ReceiptReversal::create([
                'space_id' => $space->id,
                'installment_id' => $installment->id,
                'receipt_id' => $original->id,
                'account_id' => $original->account_id,
                'user_id' => $user->id,
                'reason' => $reason,
            ]);
            AccountMovement::create([
                'account_id' => $original->account_id,
                'receipt_reversal_id' => $reversal->id,
                'amount_cents' => -$original->amount_cents,
                'effective_date' => $original->received_on->toDateString(),
            ]);
            $installment->decrement('received_cents', $original->amount_cents);

            if ($replacement !== null) {
                $substitute = Receipt::create([
                    'space_id' => $space->id,
                    'installment_id' => $installment->id,
                    'account_id' => $replacement['account_id'],
                    'user_id' => $user->id,
                    'amount_cents' => $replacement['amount_cents'],
                    'received_on' => $replacement['received_on'],
                ]);
                AccountMovement::create([
                    'account_id' => $substitute->account_id,
                    'receipt_id' => $substitute->id,
                    'amount_cents' => $substitute->amount_cents,
                    'effective_date' => $replacement['received_on'],
                ]);
                $installment->increment('received_cents', $substitute->amount_cents);
                $reversal->update(['replacement_receipt_id' => $substitute->id]);
            }

            return ['receipt_reversal_id' => $reversal->id];
        });
    }

    /** @param array{account_id: int, amount_cents: int, received_on: string} $replacement */
    private function validateReplacement(Installment $installment, Receipt $original, ?Account $account, array $replacement): void
    {
        if ($account === null) {
            throw ValidationException::withMessages(['account_id' => 'Selecione uma conta deste espaço.']);
        }
        // O estorno pode sair de conta arquivada; o substituto só entra em conta ativa.
        if ($account->isArchived()) {
            throw ValidationException::withMessages(['account_id' => 'Esta conta está arquivada. Escolha uma conta ativa.']);
        }
        if ($replacement['received_on'] < $account->opening_balance_date->toDateString()) {
            throw ValidationException::withMessages([
                'received_on' => 'A data do recebimento não pode ser anterior ao saldo inicial da conta ('.$account->opening_balance_date->format('d/m/Y').').',
            ]);
        }
        if ($account->id === $original->account_id
            && $replacement['amount_cents'] === $original->amount_cents
            && $replacement['received_on'] === $original->received_on->toDateString()) {
            throw ValidationException::withMessages(['receipt' => 'Nada a corrigir: altere a conta, o valor ou a data.']);
        }
        $available = $installment->remainingCents() + $original->amount_cents;
        if ($replacement['amount_cents'] > $available) {
            throw ValidationException::withMessages([
                'amount' => 'O valor excede o restante da parcela após o estorno ('.Money::fromCents($available).').',
            ]);
        }
        $balance = $account->balanceCents() - ($account->id === $original->account_id ? $original->amount_cents : 0);
        if ($balance + $replacement['amount_cents'] > Money::MAX_CENTS) {
            throw ValidationException::withMessages(['amount' => 'O saldo da conta ultrapassaria o limite suportado.']);
        }
    }
}
