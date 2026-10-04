<?php

declare(strict_types=1);

namespace App\Domain\Receivables;

use DateTimeImmutable;
use DateTimeZone;
use InvalidArgumentException;

final class InstallmentSchedule
{
    /** @return list<array{number: int, amount: string, due_date: string}> */
    public static function generate(string $total, int $count, string $firstDueDate): array
    {
        $cents = Money::toCents($total);
        if ($count < 1 || $count > 1200 || $cents < $count) {
            throw new InvalidArgumentException('Informe de 1 a 1200 parcelas, cada uma com pelo menos um centavo.');
        }
        $date = self::parseDate($firstDueDate);
        $monthIndex = ((int) $date->format('Y')) * 12 + (int) $date->format('n') - 1;
        if (intdiv($monthIndex + $count - 1, 12) > 9999) {
            throw new InvalidArgumentException('O término do acordo ultrapassa o ano permitido.');
        }

        $referenceDay = (int) $date->format('j');
        $base = intdiv($cents, $count);
        $remainder = $cents % $count;
        $schedule = [];
        for ($index = 0; $index < $count; $index++) {
            $year = intdiv($monthIndex + $index, 12);
            $month = ($monthIndex + $index) % 12 + 1;
            $monthStart = $date->setDate($year, $month, 1);
            $day = min($referenceDay, (int) $monthStart->format('t'));
            $schedule[] = [
                'number' => $index + 1,
                'amount' => Money::fromCents($base + ($index < $remainder ? 1 : 0)),
                'due_date' => $monthStart->setDate($year, $month, $day)->format('Y-m-d'),
            ];
        }

        return $schedule;
    }

    private static function parseDate(string $value): DateTimeImmutable
    {
        if (! preg_match('/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/', $value) || substr($value, 0, 4) === '0000') {
            throw new InvalidArgumentException('Informe uma data válida no formato AAAA-MM-DD.');
        }
        $date = DateTimeImmutable::createFromFormat('!Y-m-d', $value, new DateTimeZone('UTC'));
        if ($date === false || $date->format('Y-m-d') !== $value) {
            throw new InvalidArgumentException('Informe uma data válida no formato AAAA-MM-DD.');
        }

        return $date;
    }
}
