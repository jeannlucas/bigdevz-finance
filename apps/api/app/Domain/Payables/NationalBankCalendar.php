<?php

declare(strict_types=1);

namespace App\Domain\Payables;

use DateTimeImmutable;
use DateTimeZone;
use InvalidArgumentException;

/** Calendário nacional para boletos comuns, conforme CMN 4.880 e Febraban. */
final class NationalBankCalendar
{
    private const FIXED_HOLIDAYS = ['01-01', '04-21', '05-01', '09-07', '10-12', '11-02', '11-15', '11-20', '12-25'];

    public static function onOrAfter(string $date): string
    {
        $day = new DateTimeImmutable($date, new DateTimeZone('UTC'));
        $holidays = [];
        while (true) {
            $year = (int) $day->format('Y');
            if ($year > 9999) {
                throw new InvalidArgumentException('O próximo dia útil excede o limite do calendário.');
            }
            $holidays[$year] ??= self::holidays($year);
            if ((int) $day->format('N') <= 5 && ! in_array($day->format('m-d'), $holidays[$year], true)) {
                return $day->format('Y-m-d');
            }
            $day = $day->modify('+1 day');
        }
    }

    /** @return list<string> */
    private static function holidays(int $year): array
    {
        $easter = self::easter($year);
        $yearEnd = new DateTimeImmutable(sprintf('%04d-12-31', $year), new DateTimeZone('UTC'));
        if ((int) $yearEnd->format('N') > 5) {
            $yearEnd = $yearEnd->modify('last Friday');
        }

        return [
            ...self::FIXED_HOLIDAYS,
            $easter->modify('-48 days')->format('m-d'),
            $easter->modify('-47 days')->format('m-d'),
            $easter->modify('-2 days')->format('m-d'),
            $easter->modify('+60 days')->format('m-d'),
            $yearEnd->format('m-d'),
        ];
    }

    /** Computus gregoriano (Meeus/Jones/Butcher), independente da extensão calendar. */
    private static function easter(int $year): DateTimeImmutable
    {
        $goldenNumber = $year % 19;
        $century = intdiv($year, 100);
        $yearOfCentury = $year % 100;
        $solarCorrection = intdiv($century + 8, 25);
        $lunarCorrection = intdiv($century - $solarCorrection + 1, 3);
        $epact = (19 * $goldenNumber + $century - intdiv($century, 4) - $lunarCorrection + 15) % 30;
        $weekdayCorrection = (32 + 2 * ($century % 4) + 2 * intdiv($yearOfCentury, 4) - $epact - ($yearOfCentury % 4)) % 7;
        $exception = intdiv($goldenNumber + 11 * $epact + 22 * $weekdayCorrection, 451);
        $date = $epact + $weekdayCorrection - 7 * $exception + 114;

        return new DateTimeImmutable(
            sprintf('%04d-%02d-%02d', $year, intdiv($date, 31), $date % 31 + 1),
            new DateTimeZone('UTC'),
        );
    }
}
