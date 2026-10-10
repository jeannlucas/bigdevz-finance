<?php

declare(strict_types=1);

namespace App\Domain\Receivables;

use DateTimeImmutable;
use DateTimeZone;
use InvalidArgumentException;

/**
 * Datas mensais com dia de referência: meses curtos usam o último dia
 * válido (31 → 28/29 em fevereiro, conforme o ano bissexto) e o mês seguinte
 * volta ao dia de referência. Usada por parcelas, recorrências e faturas.
 */
final class MonthlyDate
{
    /** Data no mês indicado, com o dia de referência ajustado ao mês. */
    public static function in(int $year, int $month, int $referenceDay): string
    {
        if ($month < 1 || $month > 12 || $year < 1 || $year > 9999 || $referenceDay < 1 || $referenceDay > 31) {
            throw new InvalidArgumentException('Mês, ano ou dia de referência inválido.');
        }
        $last = (int) (new DateTimeImmutable('now', new DateTimeZone('UTC')))->setDate($year, $month, 1)->format('t');
        $day = min($referenceDay, $last);

        return sprintf('%04d-%02d-%02d', $year, $month, $day);
    }

    /** Data $offset meses depois do mês de "AAAA-MM-DD", no dia de referência. */
    public static function shift(string $date, int $offset, int $referenceDay): string
    {
        $index = ((int) substr($date, 0, 4)) * 12 + (int) substr($date, 5, 2) - 1 + $offset;

        return self::in(intdiv($index, 12), $index % 12 + 1, $referenceDay);
    }

    /** Primeiro dia do mês de "AAAA-MM-DD" (identifica o ciclo). */
    public static function cycle(string $date): string
    {
        return substr($date, 0, 7).'-01';
    }
}
