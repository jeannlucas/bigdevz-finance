<?php

namespace App\Actions\Payables;

use App\Models\ObligationChange;
use App\Models\Space;
use App\Models\User;

/** Trilha de alterações de obrigações, recorrências e cartões. */
trait RecordsChanges
{
    /** @param array<string, mixed> $before @param array<string, mixed> $after */
    private function record(User $user, Space $space, string $subject, int $id, string $action, array $before, array $after, ?string $reason = null): void
    {
        ObligationChange::create([
            'space_id' => $space->id, 'user_id' => $user->id, 'subject' => $subject, 'subject_id' => $id,
            'action' => $action, 'before' => $before, 'after' => $after, 'reason' => $reason,
        ]);
    }
}
