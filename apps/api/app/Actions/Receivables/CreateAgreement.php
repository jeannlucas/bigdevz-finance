<?php

namespace App\Actions\Receivables;

use App\Domain\Receivables\InstallmentSchedule;
use App\Domain\Receivables\Money;
use App\Models\Agreement;
use App\Models\Space;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;

/** Cadastra o acordo e todas as parcelas de uma vez; não movimenta contas. */
class CreateAgreement
{
    public function handle(Space $space, string $description, string $total, int $count, string $firstDueDate, ?int $categoryId = null): Agreement
    {
        if ($categoryId !== null) {
            $space->categories()->where('type', 'income')->findOrFail($categoryId);
        }

        try {
            $schedule = InstallmentSchedule::generate($total, $count, $firstDueDate);
        } catch (InvalidArgumentException $error) {
            throw ValidationException::withMessages(['installment_count' => $error->getMessage()]);
        }

        return DB::transaction(function () use ($space, $description, $total, $count, $firstDueDate, $schedule, $categoryId) {
            $agreement = $space->agreements()->create([
                'description' => $description,
                'total_cents' => Money::toCents($total),
                'installment_count' => $count,
                'first_due_date' => $firstDueDate,
                'category_id' => $categoryId,
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
}
