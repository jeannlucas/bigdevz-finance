<?php

namespace App\Actions\Accounts;

use App\Models\Account;
use App\Models\Space;
use Illuminate\Support\Facades\DB;

/**
 * Arquiva ou reativa uma conta. Não muda dinheiro nem histórico. Trava a
 * conta (FOR UPDATE), como recebimentos e correções que a escolhem como
 * destino: um recebimento em curso termina antes do arquivamento, ou vê a
 * conta já arquivada e é recusado. Repetir o mesmo pedido não muda nada.
 */
class ArchiveAccount
{
    public function handle(Space $space, int $accountId, bool $archived): Account
    {
        return DB::transaction(function () use ($space, $accountId, $archived) {
            $account = Account::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($accountId);
            if ($account->isArchived() !== $archived) {
                $account->archived_at = $archived ? now() : null;
                $account->save();
            }

            return $account;
        });
    }
}
