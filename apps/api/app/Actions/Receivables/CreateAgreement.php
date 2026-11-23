<?php

namespace App\Actions\Receivables;

use App\Domain\Receivables\InstallmentSchedule;
use App\Domain\Receivables\Money;
use App\Models\Agreement;
use App\Models\Space;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;

/** Cadastra o acordo avulso, parcelado ou recorrente; não movimenta contas. */
class CreateAgreement
{
    public function __construct(
        private readonly GenerateReceivables $generate = new GenerateReceivables,
    ) {}

    public function handle(
        Space $space,
        string $description,
        string $total,
        int $count,
        string $firstDueDate,
        ?int $categoryId = null,
        ?string $idempotencyKey = null,
    ): Agreement {
        if ($categoryId !== null) {
            $space->categories()->where('type', 'income')->findOrFail($categoryId);
        }

        try {
            $schedule = InstallmentSchedule::generate($total, $count, $firstDueDate);
        } catch (InvalidArgumentException $error) {
            throw ValidationException::withMessages(['installment_count' => $error->getMessage()]);
        }

        return DB::transaction(function () use ($space, $description, $total, $count, $firstDueDate, $schedule, $categoryId, $idempotencyKey) {
            $agreement = $space->agreements()->create([
                'kind' => $count === 1 ? 'single' : 'installment',
                'description' => $description,
                'total_cents' => Money::toCents($total),
                'installment_count' => $count,
                'first_due_date' => $firstDueDate,
                'category_id' => $categoryId,
                'idempotency_key' => $idempotencyKey,
            ]);
            $agreement->installments()->createMany(array_map(static fn (array $item) => [
                'space_id' => $space->id,
                'number' => $item['number'],
                'amount_cents' => Money::toCents($item['amount']),
                'due_date' => $item['due_date'],
            ], $schedule));

            return $agreement;
        });
    }

    public function recurring(
        User $user,
        Space $space,
        array $data,
        ?string $idempotencyKey = null,
    ): Agreement {
        $categoryId = isset($data['category_id']) ? (int) $data['category_id'] : null;
        if ($categoryId !== null) {
            $space->categories()->where('type', 'income')->findOrFail($categoryId);
        }

        $plan = GenerateReceivables::initialPlan($data['start_date'], $data['end_date'] ?? null, $data['approved_until']);
        if ($data['approved_until'] > GenerateReceivables::horizon()) {
            throw ValidationException::withMessages([
                'approved_until' => 'O período aprovado vai além do horizonte atual. Revise a recorrência de novo.',
            ]);
        }

        $isVariable = filter_var($data['is_variable'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $amountCents = (! empty($data['amount'])) ? Money::toCents($data['amount']) : null;
        $estimatedCents = (! empty($data['estimated_amount'])) ? Money::toCents($data['estimated_amount']) : null;

        $checkCents = $amountCents ?? ($estimatedCents ?? 0);
        $past = GenerateReceivables::pastOf($plan, $checkCents);
        if ($past['count'] > 0 && ! filter_var($data['confirm_past'] ?? false, FILTER_VALIDATE_BOOLEAN)) {
            $totalText = $checkCents > 0 ? ' (total '.Money::formatAggregate($past['total_cents']).')' : '';
            throw ValidationException::withMessages([
                'confirm_past' => "Confirme a criação das {$past['count']} ocorrências já vencidas{$totalText}.",
            ]);
        }

        return DB::transaction(function () use ($space, $data, $isVariable, $amountCents, $estimatedCents, $categoryId, $idempotencyKey) {
            $agreement = $space->agreements()->create([
                'kind' => 'recurring',
                'description' => $data['description'],
                'is_variable' => $isVariable,
                'amount_cents' => $amountCents,
                'estimated_amount_cents' => $estimatedCents,
                'start_date' => $data['start_date'],
                'reference_day' => (int) substr($data['start_date'], 8, 2),
                'end_date' => $data['end_date'] ?? null,
                'initial_until' => $data['approved_until'],
                'category_id' => $categoryId,
                'idempotency_key' => $idempotencyKey,
            ]);

            $locked = Agreement::query()->where('space_id', $space->id)->lockForUpdate()->findOrFail($agreement->id);
            $this->generate->forAgreement($locked, $data['approved_until']);

            return $agreement;
        });
    }
}
