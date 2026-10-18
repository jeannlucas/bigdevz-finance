<?php

declare(strict_types=1);

namespace App\Domain\Receivables;

use InvalidArgumentException;

final class Money
{
    public const MAX_CENTS = 99999999999999;

    public static function toCents(string $decimal): int
    {
        if (! preg_match('/\A(0|[1-9][0-9]{0,11})\.([0-9]{2})\z/', $decimal, $parts)) {
            throw new InvalidArgumentException('Informe um valor decimal com duas casas dentro do limite permitido.');
        }

        return ((int) $parts[1]) * 100 + (int) $parts[2];
    }

    /**
     * Valores sempre positivos na entrada (toCents). Na saída, saldos podem
     * ser negativos depois de pagamentos (decisão 0006): "-250.00".
     */
    public static function fromCents(int $cents): string
    {
        if ($cents < -self::MAX_CENTS || $cents > self::MAX_CENTS) {
            throw new InvalidArgumentException('Valor fora do limite permitido.');
        }
        $abs = abs($cents);

        return ($cents < 0 ? '-' : '').intdiv($abs, 100).'.'.str_pad((string) ($abs % 100), 2, '0', STR_PAD_LEFT);
    }

    /**
     * Formata totais agregados (saldos consolidados, prévias de recorrência)
     * que podem ultrapassar MAX_CENTS, preservando a exatidão em centavos
     * sem float e sem truncamento até o limite de inteiros de 64 bits.
     */
    public static function formatAggregate(int|string $cents): string
    {
        $str = (string) $cents;
        if (! preg_match('/\A(-?)([0-9]+)\z/', $str, $matches)) {
            throw new InvalidArgumentException('Valor agregado deve ser um número inteiro de centavos.');
        }

        $sign = $matches[1];
        $rawDigits = ltrim($matches[2], '0');
        if ($rawDigits === '') {
            $digits = '0';
            $sign = '';
        } else {
            $digits = $rawDigits;
        }

        if (strlen($digits) > 19) {
            throw new InvalidArgumentException('Valor agregado ultrapassa a precisão inteira suportada.');
        }
        if (strlen($digits) === 19) {
            $limit = $sign === '-' ? '9223372036854775808' : '9223372036854775807';
            if (strcmp($digits, $limit) > 0) {
                throw new InvalidArgumentException('Valor agregado ultrapassa a precisão inteira suportada.');
            }
        }

        $len = strlen($digits);
        if ($len <= 2) {
            $quotient = '0';
            $remainder = str_pad($digits, 2, '0', STR_PAD_LEFT);
        } else {
            $quotient = substr($digits, 0, $len - 2);
            $remainder = substr($digits, -2);
        }

        if ($sign === '-' && ($quotient !== '0' || $remainder !== '00')) {
            return '-'.$quotient.'.'.$remainder;
        }

        return $quotient.'.'.$remainder;
    }

    /**
     * Soma de forma exata uma sequência de centavos usando bcmath,
     * prevenindo conversão implícita para float em caso de overflow intermediário.
     *
     * @param  iterable<int|string>  $centsList
     */
    public static function sum(iterable $centsList): string
    {
        $total = '0';
        foreach ($centsList as $cents) {
            $total = bcadd($total, (string) ($cents ?? 0), 0);
        }

        return self::formatAggregate($total);
    }
}
