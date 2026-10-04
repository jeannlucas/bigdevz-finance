<?php

namespace App\Actions\Receivables;

use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Installment;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\User;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Registra um recebimento total ou parcial de uma parcela.
 *
 * Recebimento, movimentação da conta e valor recebido da parcela são gravados
 * na mesma transação. Parcela e conta são travadas (FOR UPDATE, nesta ordem)
 * para que recebimentos simultâneos não ultrapassem o valor devido; a CHECK
 * received_cents <= amount_cents no banco é a última barreira.
 */
class ReceiveInstallment
{
    public function handle(
        User $user,
        Space $space,
        int $installmentId,
        int $accountId,
        int $amountCents,
        string $receivedOn,
        string $idempotencyKey,
    ): ReceiptOutcome {
        $fingerprint = hash('sha256', implode('|', [$installmentId, $accountId, $amountCents, $receivedOn]));

        try {
            return DB::transaction(function () use ($user, $space, $installmentId, $accountId, $amountCents, $receivedOn, $idempotencyKey, $fingerprint) {
                $installment = Installment::query()
                    ->where('space_id', $space->id)
                    ->lockForUpdate()
                    ->findOrFail($installmentId);

                // Conferido depois do lock: um reenvio concorrente da mesma
                // operação enxerga o recebimento já efetivado.
                if ($replay = $this->replay($space, $idempotencyKey, $fingerprint)) {
                    return $replay;
                }

                $account = Account::query()->where('space_id', $space->id)->lockForUpdate()->find($accountId);
                if ($account === null) {
                    throw ValidationException::withMessages(['account_id' => 'Selecione uma conta deste espaço.']);
                }
                if ($receivedOn < $account->opening_balance_date->toDateString()) {
                    throw ValidationException::withMessages([
                        'received_on' => 'A data do recebimento não pode ser anterior ao saldo inicial da conta ('.$account->opening_balance_date->format('d/m/Y').').',
                    ]);
                }
                if ($amountCents > $installment->remainingCents()) {
                    throw ValidationException::withMessages([
                        'amount' => 'O valor excede o restante da parcela ('.Money::fromCents($installment->remainingCents()).').',
                    ]);
                }
                if ($account->balanceCents() + $amountCents > Money::MAX_CENTS) {
                    throw ValidationException::withMessages(['amount' => 'O saldo da conta ultrapassaria o limite suportado.']);
                }

                $receipt = Receipt::create([
                    'space_id' => $space->id,
                    'installment_id' => $installment->id,
                    'account_id' => $account->id,
                    'user_id' => $user->id,
                    'amount_cents' => $amountCents,
                    'received_on' => $receivedOn,
                    'idempotency_key' => $idempotencyKey,
                    'request_fingerprint' => $fingerprint,
                ]);
                AccountMovement::create([
                    'account_id' => $account->id,
                    'receipt_id' => $receipt->id,
                    'amount_cents' => $amountCents,
                    'effective_date' => $receivedOn,
                ]);
                // Incremento no SQL: se o lock regredir, a CHECK do banco ainda barra o excesso.
                $installment->increment('received_cents', $amountCents);

                return new ReceiptOutcome($receipt, created: true);
            });
        } catch (UniqueConstraintViolationException $error) {
            // Mesma chave gravada por outra requisição concorrente.
            return $this->replay($space, $idempotencyKey, $fingerprint) ?? throw $error;
        }
    }

    private function replay(Space $space, string $key, string $fingerprint): ?ReceiptOutcome
    {
        $existing = Receipt::query()->where('space_id', $space->id)->where('idempotency_key', $key)->first();
        if ($existing === null) {
            return null;
        }
        if (! hash_equals($existing->request_fingerprint, $fingerprint)) {
            throw new IdempotencyConflict;
        }

        return new ReceiptOutcome($existing, created: false);
    }
}
