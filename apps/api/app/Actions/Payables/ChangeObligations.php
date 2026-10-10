<?php

namespace App\Actions\Payables;

use App\Domain\Receivables\Money;
use App\Models\Card;
use App\Models\Payable;
use App\Models\Recurrence;
use App\Models\Space;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Edição, cancelamento e encerramento, sempre com trilha. Trava a linha
 * alterada (FOR UPDATE): pagamentos travam a obrigação antes de gravar, então
 * o valor nunca fica abaixo do pago líquido nem se cancela algo pago.
 */
class ChangeObligations
{
    use RecordsChanges;

    public function __construct(private readonly GenerateObligations $generate) {}

    /**
     * Esta ocorrência/obrigação. Marca edited_at: edições da recorrência não
     * a sobrescrevem depois. Em fatura, informar ou corrigir o total.
     *
     * @param  array{description?: string, payee?: ?string, amount?: ?string, due_date?: string}  $data
     */
    public function edit(User $user, Space $space, int $payableId, array $data, ?string $reason): Payable
    {
        return DB::transaction(function () use ($user, $space, $payableId, $data, $reason) {
            $payable = Payable::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($payableId);
            if ($payable->isCancelled()) {
                throw ValidationException::withMessages(['payable' => 'Obrigação cancelada não pode ser editada.']);
            }
            $changes = [];
            foreach (['description', 'payee', 'due_date'] as $field) {
                if (array_key_exists($field, $data) && $data[$field] !== $this->value($payable, $field)) {
                    $changes[$field] = $data[$field];
                }
            }
            if (array_key_exists('amount', $data)) {
                $cents = $data['amount'] === null ? null : Money::toCents($data['amount']);
                if ($cents === null && $payable->kind !== Payable::CARD_BILL) {
                    throw ValidationException::withMessages(['amount' => 'Informe o valor.']);
                }
                if ($cents !== null && $cents < $payable->paid_cents) {
                    throw ValidationException::withMessages([
                        'amount' => 'O valor não pode ficar abaixo do pago líquido ('.Money::fromCents($payable->paid_cents).').',
                    ]);
                }
                if ($cents === null && $payable->paid_cents > 0) {
                    throw ValidationException::withMessages(['amount' => 'A fatura tem pagamento: informe um total.']);
                }
                if ($cents !== $payable->amount_cents) {
                    $changes['amount_cents'] = $cents;
                }
            }
            if ($changes === []) {
                return $payable;
            }
            $before = array_map(fn ($field) => $this->value($payable, $field), array_combine(array_keys($changes), array_keys($changes)));
            $payable->fill($changes);
            $payable->edited_at = now();
            $payable->save();
            $this->record($user, $space, 'payable', $payable->id, 'edit', $before, $changes, $reason);

            return $payable;
        });
    }

    /** Sem pagamento ativo (pago líquido zero). Repetir não muda nada. */
    public function cancel(User $user, Space $space, int $payableId, string $reason): Payable
    {
        return DB::transaction(function () use ($user, $space, $payableId, $reason) {
            $payable = Payable::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($payableId);
            if ($payable->isCancelled()) {
                return $payable;
            }
            if ($payable->paid_cents > 0) {
                throw ValidationException::withMessages([
                    'payable' => 'A obrigação tem pagamento ativo. Estorne os pagamentos antes de cancelar.',
                ]);
            }
            $payable->cancelled_at = now();
            $payable->cancel_reason = $reason;
            $payable->save();
            $this->record($user, $space, 'payable', $payable->id, 'cancel', ['status' => 'open'], ['status' => 'cancelled'], $reason);

            return $payable;
        });
    }

    /**
     * Futuras: a recorrência e as ocorrências com vencimento de hoje em
     * diante, sem pagamento, não canceladas e não editadas individualmente.
     * Pagas, parciais, vencidas e editadas ficam como estão.
     *
     * @param  array{description?: string, payee?: ?string, amount?: string}  $data
     */
    public function editRecurrence(User $user, Space $space, int $recurrenceId, array $data): Recurrence
    {
        return DB::transaction(function () use ($user, $space, $recurrenceId, $data) {
            $recurrence = Recurrence::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($recurrenceId);
            $changes = [];
            foreach (['description', 'payee'] as $field) {
                if (array_key_exists($field, $data) && $data[$field] !== $recurrence->{$field}) {
                    $changes[$field] = $data[$field];
                }
            }
            if (isset($data['amount']) && Money::toCents($data['amount']) !== $recurrence->amount_cents) {
                $changes['amount_cents'] = Money::toCents($data['amount']);
            }
            if ($changes === []) {
                return $recurrence;
            }
            $before = array_intersect_key($recurrence->only(['description', 'payee', 'amount_cents']), $changes);
            $recurrence->update($changes);
            $affected = $this->futureOccurrences($recurrence)->update($changes + ['updated_at' => now()]);
            $this->record($user, $space, 'recurrence', $recurrence->id, 'edit', $before, $changes + ['future_occurrences' => $affected]);

            return $recurrence;
        });
    }

    /**
     * Encerra a recorrência em $endDate: não gera mais ciclos depois dela e
     * cancela as ocorrências seguintes sem pagamento. Não estorna pagamentos
     * nem apaga débitos: vencidas e com pagamento parcial continuam.
     */
    public function endRecurrence(User $user, Space $space, int $recurrenceId, string $endDate, ?string $reason): Recurrence
    {
        return DB::transaction(function () use ($user, $space, $recurrenceId, $endDate, $reason) {
            $recurrence = Recurrence::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($recurrenceId);
            if ($endDate < $recurrence->start_date->toDateString()) {
                throw ValidationException::withMessages(['end_date' => 'O encerramento não pode ser antes do início.']);
            }
            $before = ['end_date' => $recurrence->end_date?->toDateString()];
            $recurrence->update(['end_date' => $endDate]);
            $cancelled = $recurrence->occurrences()->getQuery()
                ->where('due_date', '>', $endDate)->where('paid_cents', 0)->whereNull('cancelled_at')
                ->update(['cancelled_at' => now(), 'cancel_reason' => 'Recorrência encerrada', 'updated_at' => now()]);
            $this->record($user, $space, 'recurrence', $recurrence->id, 'end', $before, ['end_date' => $endDate, 'cancelled_occurrences' => $cancelled], $reason);

            return $recurrence;
        });
    }

    /** Cartão arquivado deixa de gerar faturas; as existentes ficam pagáveis. */
    public function archiveCard(User $user, Space $space, int $cardId, bool $archived): Card
    {
        return DB::transaction(function () use ($user, $space, $cardId, $archived) {
            $card = Card::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($cardId);
            if ($card->isArchived() !== $archived) {
                $card->archived_at = $archived ? now() : null;
                $card->save();
                $this->record($user, $space, 'card', $card->id, $archived ? 'archive' : 'unarchive', [], []);
                if (! $archived) {
                    $this->generate->forCard($card);
                }
            }

            return $card;
        });
    }

    private function futureOccurrences(Recurrence $recurrence)
    {
        return $recurrence->occurrences()->getQuery()
            ->where('due_date', '>=', GenerateObligations::today())
            ->where('paid_cents', 0)->whereNull('cancelled_at')->whereNull('edited_at');
    }

    private function value(Payable $payable, string $field): mixed
    {
        return $field === 'due_date' ? $payable->due_date->toDateString() : $payable->{$field};
    }
}
