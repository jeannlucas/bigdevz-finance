<?php

namespace App\Actions\Receivables;

use App\Actions\Payables\RecordsChanges;
use App\Domain\Receivables\InstallmentSchedule;
use App\Domain\Receivables\Money;
use App\Models\Agreement;
use App\Models\Space;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;

class ChangeAgreements
{
    use RecordsChanges;

    /**
     * @param  array{description?: string, category_id?: ?int, total?: string, installment_count?: int, first_due_date?: string}  $data
     */
    public function edit(User $user, Space $space, int $agreementId, array $data, ?string $reason = null): Agreement
    {
        return DB::transaction(function () use ($user, $space, $agreementId, $data, $reason) {
            $agreement = Agreement::query()
                ->where('space_id', $space->id)
                ->lockForUpdate()
                ->findOrFail($agreementId);

            if ($agreement->isCancelled()) {
                throw ValidationException::withMessages([
                    'agreement' => 'Conta a receber cancelada não pode ser editada.',
                ]);
            }

            $changes = [];
            if (array_key_exists('description', $data) && $data['description'] !== $agreement->description) {
                $changes['description'] = $data['description'];
            }
            if (array_key_exists('category_id', $data) && $data['category_id'] !== $agreement->category_id) {
                if ($data['category_id'] !== null) {
                    $space->categories()->where('type', 'income')->findOrFail($data['category_id']);
                }
                $changes['category_id'] = $data['category_id'];
            }

            $reschedule = array_key_exists('total', $data)
                || array_key_exists('installment_count', $data)
                || array_key_exists('first_due_date', $data);

            if ($reschedule) {
                $receivedCents = (int) $agreement->installments()->sum('received_cents');
                if ($receivedCents > 0) {
                    throw ValidationException::withMessages([
                        'total' => 'Não é possível alterar o valor ou parcelamento de um acordo com recebimentos ativos.',
                    ]);
                }

                $newTotalStr = $data['total'] ?? Money::fromCents($agreement->total_cents);
                $newCount = isset($data['installment_count']) ? (int) $data['installment_count'] : $agreement->installment_count;
                $newFirstDueDate = $data['first_due_date'] ?? $agreement->first_due_date->toDateString();

                try {
                    $schedule = InstallmentSchedule::generate($newTotalStr, $newCount, $newFirstDueDate);
                } catch (InvalidArgumentException $e) {
                    throw ValidationException::withMessages(['installment_count' => $e->getMessage()]);
                }

                $newTotalCents = Money::toCents($newTotalStr);
                if ($newTotalCents !== $agreement->total_cents) {
                    $changes['total_cents'] = $newTotalCents;
                }
                if ($newCount !== $agreement->installment_count) {
                    $changes['installment_count'] = $newCount;
                }
                if ($newFirstDueDate !== $agreement->first_due_date->toDateString()) {
                    $changes['first_due_date'] = $newFirstDueDate;
                }

                // Recria as parcelas recalculadas
                $agreement->installments()->delete();
                $agreement->installments()->createMany(array_map(static fn (array $item) => [
                    'space_id' => $space->id,
                    'number' => $item['number'],
                    'amount_cents' => Money::toCents($item['amount']),
                    'due_date' => $item['due_date'],
                ], $schedule));
            }

            if ($changes === []) {
                return $agreement;
            }

            $before = array_intersect_key($agreement->toArray(), $changes);
            $agreement->fill($changes);
            $agreement->edited_at = now();
            $agreement->save();

            $this->record($user, $space, 'agreement', $agreement->id, 'edit', $before, $changes, $reason);

            return $agreement;
        });
    }

    public function cancel(User $user, Space $space, int $agreementId, string $reason): Agreement
    {
        return DB::transaction(function () use ($user, $space, $agreementId, $reason) {
            $agreement = Agreement::query()
                ->where('space_id', $space->id)
                ->with('installments')
                ->lockForUpdate()
                ->findOrFail($agreementId);

            if ($agreement->isCancelled()) {
                return $agreement;
            }

            $receivedCents = $agreement->installments->sum('received_cents');
            if ($receivedCents > 0) {
                throw ValidationException::withMessages([
                    'agreement' => 'O acordo tem recebimento ativo. Estorne os recebimentos antes de cancelar.',
                ]);
            }

            $agreement->cancelled_at = now();
            $agreement->cancel_reason = $reason;
            $agreement->save();

            $this->record($user, $space, 'agreement', $agreement->id, 'cancel', ['status' => 'open'], ['status' => 'cancelled'], $reason);

            return $agreement;
        });
    }
}
