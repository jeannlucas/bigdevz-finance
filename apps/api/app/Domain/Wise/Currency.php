<?php

namespace App\Domain\Wise;

use Illuminate\Validation\ValidationException;

final class Currency
{
    public const SCALES = [
        'BRL' => 2, 'AUD' => 2, 'CAD' => 2, 'CHF' => 2, 'CNY' => 2, 'EUR' => 2,
        'GBP' => 2, 'HKD' => 2, 'JPY' => 0, 'KRW' => 0, 'KWD' => 3,
        'MXN' => 2, 'NZD' => 2, 'PLN' => 2, 'SGD' => 2, 'USD' => 2,
    ];

    public static function parse(string $currency, string $value, string $field = 'opening_balance'): int
    {
        $scale = self::SCALES[$currency];
        $pattern = $scale === 0 ? '/^\d{1,14}$/D' : '/^\d{1,'.(14 - $scale).'}\.\d{'.$scale.'}$/D';
        if (! preg_match($pattern, $value)) {
            throw ValidationException::withMessages([$field => "Informe o valor na escala de $currency."]);
        }

        return (int) str_replace('.', '', $value);
    }

    public static function format(string $currency, int $units): string
    {
        $scale = self::SCALES[$currency];
        if ($scale === 0) {
            return (string) $units;
        }
        $digits = str_pad((string) $units, $scale + 1, '0', STR_PAD_LEFT);

        return substr($digits, 0, -$scale).'.'.substr($digits, -$scale);
    }
}
