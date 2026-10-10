<?php

namespace App\Actions\Payables;

use App\Domain\Receivables\MonthlyDate;
use App\Models\Card;
use App\Models\Payable;
use App\Models\Recurrence;
use Illuminate\Support\Facades\DB;

/**
 * Gera as ocorrências de recorrências e as faturas de cartões até o
 * horizonte (mês atual + 12, no fuso do produto). Idempotente: cada ciclo é
 * único no banco (UNIQUE recurrence_id/card_id + cycle) e a inserção usa
 * ON CONFLICT DO NOTHING; execuções repetidas ou simultâneas não duplicam.
 * Ciclos existentes nunca são recriados nem alterados, inclusive cancelados
 * ou editados manualmente.
 */
class GenerateObligations
{
    public const HORIZON_MONTHS = 12;

    /** Último ciclo gerado (primeiro dia do mês). */
    public static function horizon(): string
    {
        return MonthlyDate::cycle(MonthlyDate::shift(self::today(), self::HORIZON_MONTHS, 1));
    }

    public static function today(): string
    {
        return now(config('finance.timezone'))->toDateString();
    }

    /**
     * Ciclos de uma recorrência, do início até $until (primeiro dia do mês)
     * e o término, com o dia de referência ajustado a meses curtos. Mesma
     * regra para prévia, cadastro e geração automática; não depende de hoje.
     *
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
     * Gera até $until (padrão: o horizonte). Chamar com a recorrência travada
     * (FOR UPDATE) na transação.
     */
    public function forRecurrence(Recurrence $recurrence, ?string $until = null): int
    {
        $cycles = self::recurrenceCycles(
            $recurrence->start_date->toDateString(), $recurrence->reference_day,
            $recurrence->end_date?->toDateString(), min($until ?? self::horizon(), self::horizon()),
        );

        return $this->insert(array_map(fn (array $cycle) => $this->row(
            $recurrence->space_id, Payable::RECURRING, $recurrence->description, $recurrence->payee, $recurrence->amount_cents, $cycle['due_date'],
        ) + ['recurrence_id' => $recurrence->id, 'cycle' => $cycle['cycle']], $cycles));
    }

    /**
     * Faturas a partir do mês atual (nunca retroativas, nem depois de um
     * período arquivado), sem valor: o total é informado pelo usuário.
     * Chamar com o cartão travado.
     */
    public function forCard(Card $card): int
    {
        if ($card->isArchived()) {
            return 0;
        }
        $horizon = self::horizon();
        $cycle = max($card->first_cycle->toDateString(), MonthlyDate::cycle(self::today()));
        $rows = [];
        for ($offset = 0; ; $offset++) {
            $due = MonthlyDate::shift($cycle, $offset, $card->due_day);
            if (MonthlyDate::cycle($due) > $horizon) {
                break;
            }
            $rows[] = $this->row($card->space_id, Payable::CARD_BILL, 'Fatura '.$card->name.' '.substr($due, 5, 2).'/'.substr($due, 0, 4), null, null, $due) + [
                'card_id' => $card->id, 'cycle' => MonthlyDate::cycle($due),
            ];
        }

        return $this->insert($rows);
    }

    /** @return array{occurrences: int, bills: int} */
    public function all(): array
    {
        $today = self::today();
        $occurrences = 0;
        foreach (Recurrence::query()->where(fn ($q) => $q->whereNull('end_date')->orWhere('end_date', '>=', $today))->pluck('id') as $id) {
            $occurrences += DB::transaction(fn () => $this->forRecurrence(Recurrence::query()->lockForUpdate()->findOrFail($id)));
        }
        $bills = 0;
        foreach (Card::query()->whereNull('archived_at')->pluck('id') as $id) {
            $bills += DB::transaction(fn () => $this->forCard(Card::query()->lockForUpdate()->findOrFail($id)));
        }

        return ['occurrences' => $occurrences, 'bills' => $bills];
    }

    /** @return array<string, mixed> */
    private function row(int $spaceId, string $kind, string $description, ?string $payee, ?int $amount, string $due): array
    {
        $now = now();

        return [
            'space_id' => $spaceId, 'kind' => $kind, 'description' => $description, 'payee' => $payee,
            'amount_cents' => $amount, 'paid_cents' => 0, 'due_date' => $due, 'created_at' => $now, 'updated_at' => $now,
        ];
    }

    /** @param list<array<string, mixed>> $rows */
    private function insert(array $rows): int
    {
        $created = 0;
        foreach (array_chunk($rows, 200) as $chunk) {
            $created += DB::table('payables')->insertOrIgnore($chunk);
        }

        return $created;
    }
}
