<?php

declare(strict_types=1);

namespace App\Domain\Receivables;

use InvalidArgumentException;

final class Money
{
    private const MAX_CENTS = 99999999999999;

    public static function toCents(string $decimal): int
    {
        if (!preg_match('/\A(0|[1-9][0-9]{0,11})\.([0-9]{2})\z/', $decimal, $parts)) {
            throw new InvalidArgumentException('Informe um valor decimal com duas casas dentro do limite permitido.');
        }

        return ((int) $parts[1]) * 100 + (int) $parts[2];
    }

    public static function fromCents(int $cents): string
    {
        if ($cents < 0 || $cents > self::MAX_CENTS) {
            throw new InvalidArgumentException('Valor fora do limite permitido.');
        }

        return intdiv($cents, 100).'.'.str_pad((string) ($cents % 100), 2, '0', STR_PAD_LEFT);
    }
}
