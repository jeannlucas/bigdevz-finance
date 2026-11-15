<?php

declare(strict_types=1);

namespace App\Domain\Receivables;

use InvalidArgumentException;

/**
 * Cálculo determinístico da liquidação de uma obrigação com composição de
 * principal, juros de mora, multa e desconto. Tudo em centavos inteiros (int64).
 */
final class PaymentSettlement
{
    /**
     * @return array{principal_cents: int, interest_cents: int, fine_cents: int, discount_cents: int, total_cents: int}
     */
    public static function calculate(int $principalCents, int $interestCents = 0, int $fineCents = 0, int $discountCents = 0): array
    {
        if ($principalCents <= 0) {
            throw new InvalidArgumentException('Principal deve ser maior que zero.');
        }
        if ($principalCents > Money::MAX_CENTS) {
            throw new InvalidArgumentException('Principal excede o limite máximo permitido.');
        }
        if ($interestCents < 0 || $interestCents > Money::MAX_CENTS) {
            throw new InvalidArgumentException('Juros devem ser não-negativos e dentro do limite.');
        }
        if ($fineCents < 0 || $fineCents > Money::MAX_CENTS) {
            throw new InvalidArgumentException('Multa deve ser não-negativa e dentro do limite.');
        }
        if ($discountCents < 0 || $discountCents > Money::MAX_CENTS) {
            throw new InvalidArgumentException('Desconto deve ser não-negativo e dentro do limite.');
        }
        $subtotal = $principalCents + $interestCents + $fineCents;
        if ($discountCents >= $subtotal) {
            throw new InvalidArgumentException('Desconto não pode igualar ou superar o valor total devido.');
        }
        $totalCents = $subtotal - $discountCents;
        if ($totalCents <= 0 || $totalCents > Money::MAX_CENTS) {
            throw new InvalidArgumentException('Total debitado inválido ou excede o limite máximo.');
        }

        return [
            'principal_cents' => $principalCents,
            'interest_cents' => $interestCents,
            'fine_cents' => $fineCents,
            'discount_cents' => $discountCents,
            'total_cents' => $totalCents,
        ];
    }
}
