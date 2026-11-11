<?php

namespace App\Models\Concerns;

use Illuminate\Database\Eloquent\Casts\Attribute;

trait NormalizesFinancialText
{
    /**
     * Normaliza um campo de texto financeiro para gravação em MAIÚSCULAS com suporte total a Unicode UTF-8 (pt-BR).
     * Preserva null e remove espaços excedentes nas extremidades (trim).
     */
    public static function financialUpper(?string $value): ?string
    {
        if ($value === null) {
            return null;
        }

        $trimmed = trim($value);

        return $trimmed === '' ? '' : mb_strtoupper($trimmed, 'UTF-8');
    }

    /**
     * Cria um Attribute Eloquent com mutator que normaliza para maiúsculas antes de persistir.
     */
    protected static function uppercaseTextAttribute(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => static::financialUpper($value),
        );
    }
}
