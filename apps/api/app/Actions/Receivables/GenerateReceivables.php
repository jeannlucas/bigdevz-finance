<?php

namespace App\Actions\Receivables;

use App\Domain\Receivables\MonthlyDate;
use App\Models\Agreement;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Gera as ocorrências de receitas recorrentes até o horizonte (mês atual + 12).
 * Idempotente: cada ciclo é único por acordo (UNIQUE agreement_id + cycle)
 * e a inserção não duplica ciclos existentes nem altera ocorrências já baixadas.
 */
class GenerateReceivables
{
    public const HORIZON_MONTHS = 12;

    public const MAX_INITIAL_OCCURRENCES = 36;

    public static function today(): string
    {
        return now(config('finance.timezone'))->toDateString();
    }

    public static function horizon(): string
    {
        return MonthlyDate::cycle(MonthlyDate::shift(self::today(), self::HORIZON_MONTHS, 1));
    }

    /**
     * @return list<array{cycle: string, due_date: string}>
     */
    public static function recurrenceCycles(string $start, int $referenceDay, ?string $end, string $until, int $limit = PHP_INT_MAX): array
    {
        $cycles = [];
        for ($offset = 0; count($cycles) < $limit; $offset++) {
            $due = MonthlyDate::shift($start, $offset, $referenceDay);
            if (MonthlyDate::cycle($due) > $until || ($end !== null && $due > $end)) {
                break;
            }
            $cycles[] = ['cycle' => MonthlyDate::cycle($due), 'due_date' => $due];
        }

        return $cycles;
    }

    /**
     * @return list<array{cycle: string, due_date: string}>
     */
    public static function initialPlan(string $start, ?string $end, string $until): array
    {
        $cycles = self::recurrenceCycles($start, (int) substr($start, 8, 2), $end, $until, self::MAX_INITIAL_OCCURRENCES + 1);
        if ($cycles === []) {
            throw ValidationException::withMessages([
                'start_date' => 'Nenhuma ocorrência no período: o início fica depois do horizonte de 12 meses.',
            ]);
        }
        if (count($cycles) > self::MAX_INITIAL_OCCURRENCES) {
            throw ValidationException::withMessages([
                'start_date' => 'O conjunto inicial teria mais de '.self::MAX_INITIAL_OCCURRENCES.' ocorrências. Escolha um início mais recente.',
            ]);
        }

        return $cycles;
    }

    /**
     * @param  list<array{cycle: string, due_date: string}>  $plan
     * @return array{count: int, total_cents: int}
     */
    public static function pastOf(array $plan, int $amountCents): array
    {
        $today = self::today();
        $count = count(array_filter($plan, static fn (array $cycle) => $cycle['due_date'] < $today));

        return ['count' => $count, 'total_cents' => $count * $amountCents];
    }

    /**
     * Gera até $until (ou horizonte). Chamar com o Agreement travado na transação.
     */
    public function forAgreement(Agreement $agreement, ?string $until = null): int
    {
        if ($agreement->kind !== 'recurring' || $agreement->start_date === null) {
            return 0;
        }

        $targetUntil = min($until ?? self::horizon(), self::horizon());
        $cycles = self::recurrenceCycles(
            $agreement->start_date->toDateString(),
            $agreement->reference_day ?? (int) substr($agreement->start_date->toDateString(), 8, 2),
            $agreement->end_date?->toDateString(),
            $targetUntil,
        );

        if ($cycles === []) {
            return 0;
        }

        $existingCycles = DB::table('installments')
            ->where('agreement_id', $agreement->id)
            ->pluck('cycle')
            ->flip()
            ->all();

        $maxNumber = (int) DB::table('installments')
            ->where('agreement_id', $agreement->id)
            ->max('number');

        $startDate = $agreement->start_date->toDateString();
        $isVariable = (bool) $agreement->is_variable;
        $now = Carbon::now(config('finance.timezone'))->toDateTimeString();

        $rows = [];
        $insertedCount = 0;

        foreach ($cycles as $cycle) {
            if (isset($existingCycles[$cycle['cycle']])) {
                continue;
            }

            $maxNumber++;
            $amountCents = $isVariable
                ? ($cycle['due_date'] === $startDate ? $agreement->amount_cents : null)
                : $agreement->amount_cents;

            $rows[] = [
                'agreement_id' => $agreement->id,
                'space_id' => $agreement->space_id,
                'number' => $maxNumber,
                'cycle' => $cycle['cycle'],
                'due_date' => $cycle['due_date'],
                'amount_cents' => $amountCents,
                'estimated_amount_cents' => $isVariable ? $agreement->estimated_amount_cents : null,
                'received_cents' => 0,
                'created_at' => $now,
                'updated_at' => $now,
            ];
            $insertedCount++;
        }

        if ($rows !== []) {
            DB::table('installments')->insert($rows);
        }

        return $insertedCount;
    }

    public function all(): int
    {
        $total = 0;
        Agreement::query()
            ->where('kind', 'recurring')
            ->whereNull('cancelled_at')
            ->chunkById(50, function ($agreements) use (&$total) {
                foreach ($agreements as $agreement) {
                    $total += $this->forAgreement($agreement);
                }
            });

        return $total;
    }
}
