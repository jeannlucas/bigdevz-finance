<?php

namespace App\Rules;

use App\Domain\Receivables\Money;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use InvalidArgumentException;

/** Valor monetário no contrato da decisão 0002: string "1234.56". */
class MoneyAmount implements ValidationRule
{
    public function __construct(private readonly bool $positive = true) {}

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        try {
            $cents = is_string($value) ? Money::toCents($value) : null;
        } catch (InvalidArgumentException) {
            $cents = null;
        }

        if ($cents === null) {
            $fail('Informe o valor como texto com ponto e duas casas decimais, por exemplo "1500.00", até 999999999999.99.');
        } elseif ($this->positive && $cents === 0) {
            $fail('O valor precisa ser maior que zero.');
        }
    }
}
