<?php

namespace App\Actions\Transfers;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Space;
use App\Models\Transfer;
use App\Models\TransferReversal;
use App\Models\User;
use Illuminate\Validation\ValidationException;

class ReverseTransfer
{
    public function __construct(private readonly IdempotentOperations $keys) {}

    public static function fingerprint(int $transferId, mixed $reason): string
    {
        return IdempotentOperations::fingerprint(IdempotentOperations::TRANSFER_REVERSAL, $transferId, [
            'reason' => $reason,
        ]);
    }

    public function handle(
        User $user,
        Space $space,
        int $transferId,
        string $reason,
        string $key
    ): KeyedResult {
        $fingerprint = self::fingerprint($transferId, $reason);

        return $this->keys->run($user, $space, $key, IdempotentOperations::TRANSFER_REVERSAL, $fingerprint, function () use (
            $user,
            $space,
            $transferId,
            $reason
        ) {
            $transfer = Transfer::query()
                ->where(function ($q) use ($space) {
                    $q->where('space_id', $space->id)
                        ->orWhere('destination_space_id', $space->id);
                })
                ->lockForUpdate()
                ->findOrFail($transferId);

            if (TransferReversal::query()->where('transfer_id', $transfer->id)->exists()) {
                throw ValidationException::withMessages([
                    'transfer' => 'Esta transferência já foi estornada.',
                ]);
            }

            // Garante acesso e permissões em ambos os espaços
            $sourceSpace = $user->spaces()->findOrFail($transfer->space_id);
            $destinationSpace = $user->spaces()->findOrFail($transfer->destination_space_id);

            $sourceSpace->ensureCan($user, 'reverse_transfer');
            $destinationSpace->ensureCan($user, 'reverse_transfer');

            $sourceSpace->ensureDateNotClosed($transfer->transferred_at, 'estorno de transferência');
            $destinationSpace->ensureDateNotClosed($transfer->transferred_at, 'estorno de transferência');

            // Bloqueio ordenado das contas por ID para evitar deadlock
            $orderedIds = [$transfer->source_account_id, $transfer->destination_account_id];
            sort($orderedIds);

            Account::query()
                ->whereIn('id', $orderedIds)
                ->orderBy('id')
                ->lockForUpdate()
                ->get();

            $reversal = TransferReversal::create([
                'transfer_id' => $transfer->id,
                'space_id' => $sourceSpace->id,
                'destination_space_id' => $destinationSpace->id,
                'source_account_id' => $transfer->source_account_id,
                'destination_account_id' => $transfer->destination_account_id,
                'user_id' => $user->id,
                'reason' => $reason,
            ]);

            // Compensação algébrica inversa preservando auditoria:
            // 1. Crédito na conta de origem (devolve a saída)
            AccountMovement::create([
                'account_id' => $transfer->source_account_id,
                'transfer_reversal_id' => $reversal->id,
                'amount_cents' => $transfer->amount_cents,
                'effective_date' => $transfer->transferred_at->toDateString(),
            ]);

            // 2. Débito na conta de destino (devolve a entrada)
            AccountMovement::create([
                'account_id' => $transfer->destination_account_id,
                'transfer_reversal_id' => $reversal->id,
                'amount_cents' => -$transfer->amount_cents,
                'effective_date' => $transfer->transferred_at->toDateString(),
            ]);

            return ['transfer_reversal_id' => $reversal->id];
        });
    }
}
