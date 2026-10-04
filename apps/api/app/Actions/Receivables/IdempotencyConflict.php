<?php

namespace App\Actions\Receivables;

use RuntimeException;

/** Chave idempotente reutilizada com conteúdo diferente. */
class IdempotencyConflict extends RuntimeException
{
    public function __construct()
    {
        parent::__construct('Esta chave de operação já foi usada com outros dados. Gere uma nova chave para um novo recebimento.');
    }
}
