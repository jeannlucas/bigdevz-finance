<?php

namespace App\Actions\Transfers;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Space;
use App\Models\Transfer;
use App\Models\User;
use Illuminate\Validation\ValidationException;

class TransferFunds
{
    public function __construct(private readonly IdempotentOperations $keys) {}

    public static function fingerprint(
        int $sourceAccountId,
        int $destinationAccountId,
        mixed $amount,
        string $transferredAt,
        ?string $notes,
        ?int $sourceSpaceId = null,
        ?int $destinationSpaceId = null
    ): string {
        return IdempotentOperations::fingerprint(IdempotentOperations::TRANSFER, $sourceAccountId, [
            'source_space_id' => $sourceSpaceId,
            'destination_space_id' => $destinationSpaceId,
            'destination_account_id' => $destinationAccountId,
            'amount' => $amount,
            'transferred_at' => $transferredAt,
            'notes' => $notes,
        ]);
    }

    public function handle(
        User $user,
        Space $space,
        int $sourceAccountId,
        int $destinationAccountId,
        int $amountCents,
        string $transferredAt,
        ?string $notes,
        string $key,
        ?Space $destinationSpace = null
    ): KeyedResult {
        $sourceSpace = $space;
        $destSpace = $destinationSpace ?? $space;

        $fingerprint = self::fingerprint(
            $sourceAccountId,
            $destinationAccountId,
            Money::fromCents($amountCents),
            $transferredAt,
            $notes,
            $sourceSpace->id,
            $destSpace->id
        );

        return $this->keys->run($user, $sourceSpace, $key, IdempotentOperations::TRANSFER, $fingerprint, function () use (
            $user,
            $sourceSpace,
            $destSpace,
            $sourceAccountId,
            $destinationAccountId,
            $amountCents,
            $transferredAt,
            $notes
        ) {
            if ($sourceAccountId === $destinationAccountId) {
                throw ValidationException::withMessages([
                    'destination_account_id' => 'A conta de destino não pode ser a mesma conta de origem.',
                ]);
            }

            if ($amountCents <= 0 || $amountCents > Money::MAX_CENTS) {
                throw ValidationException::withMessages([
                    'amount' => 'Informe um valor positivo dentro do limite suportado.',
                ]);
            }

            $sourceSpace->ensureCan($user, 'transfer_funds');
            $destSpace->ensureCan($user, 'transfer_funds');

            $sourceSpace->ensureDateNotClosed($transferredAt, 'transferência entre contas');
            $destSpace->ensureDateNotClosed($transferredAt, 'transferência entre contas');

            // Ordena os IDs para evitar deadlock em concorrência
            $orderedIds = [$sourceAccountId, $destinationAccountId];
            sort($orderedIds);

            $accounts = Account::query()
                ->whereIn('id', $orderedIds)
                ->orderBy('id')
                ->lockForUpdate()
                ->get()
                ->keyBy('id');

            $sourceAccount = $accounts->get($sourceAccountId);
            $destinationAccount = $accounts->get($destinationAccountId);

            if ($sourceAccount === null || $sourceAccount->space_id !== $sourceSpace->id) {
                throw ValidationException::withMessages([
                    'source_account_id' => 'Conta de origem inválida ou pertencente a outro espaço.',
                ]);
            }

            if ($destinationAccount === null || $destinationAccount->space_id !== $destSpace->id) {
                throw ValidationException::withMessages([
                    'destination_account_id' => 'Conta de destino inválida ou pertencente a outro espaço.',
                ]);
            }

            if ($sourceAccount->isArchived()) {
                throw ValidationException::withMessages([
                    'source_account_id' => 'A conta de origem está arquivada e não pode realizar transferências.',
                ]);
            }

            if ($destinationAccount->isArchived()) {
                throw ValidationException::withMessages([
                    'destination_account_id' => 'A conta de destino está arquivada e não pode receber transferências.',
                ]);
            }

            if ($transferredAt < $sourceAccount->opening_balance_date->toDateString()) {
                throw ValidationException::withMessages([
                    'transferred_at' => 'A data da transferência não pode ser anterior ao saldo inicial da conta de origem ('.$sourceAccount->opening_balance_date->format('d/m/Y').').',
                ]);
            }

            if ($transferredAt < $destinationAccount->opening_balance_date->toDateString()) {
                throw ValidationException::withMessages([
                    'transferred_at' => 'A data da transferência não pode ser anterior ao saldo inicial da conta de destino ('.$destinationAccount->opening_balance_date->format('d/m/Y').').',
                ]);
            }

            $resultingSource = $sourceAccount->balanceCents() - $amountCents;
            if ($resultingSource < -Money::MAX_CENTS) {
                throw ValidationException::withMessages([
                    'amount' => 'O saldo da conta de origem ultrapassaria o limite suportado.',
                ]);
            }

            $resultingDestination = $destinationAccount->balanceCents() + $amountCents;
            if ($resultingDestination > Money::MAX_CENTS) {
                throw ValidationException::withMessages([
                    'amount' => 'O saldo da conta de destino ultrapassaria o limite suportado.',
                ]);
            }

            $transfer = Transfer::create([
                'space_id' => $sourceSpace->id,
                'destination_space_id' => $destSpace->id,
                'user_id' => $user->id,
                'source_account_id' => $sourceAccount->id,
                'destination_account_id' => $destinationAccount->id,
                'amount_cents' => $amountCents,
                'transferred_at' => $transferredAt,
                'notes' => $notes,
            ]);

            AccountMovement::create([
                'account_id' => $sourceAccount->id,
                'transfer_id' => $transfer->id,
                'amount_cents' => -$amountCents,
                'effective_date' => $transferredAt,
            ]);

            AccountMovement::create([
                'account_id' => $destinationAccount->id,
                'transfer_id' => $transfer->id,
                'amount_cents' => $amountCents,
                'effective_date' => $transferredAt,
            ]);

            return ['transfer_id' => $transfer->id];
        });
    }
}
