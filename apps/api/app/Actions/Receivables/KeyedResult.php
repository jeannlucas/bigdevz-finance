<?php

namespace App\Actions\Receivables;

use App\Models\IdempotencyKey;

/** Decisão de uma chave idempotente: concluída ou recusada, nova ou repetida. */
final class KeyedResult
{
    /** @param array<string, list<string>> $errors */
    public function __construct(
        public readonly string $status,
        public readonly bool $replayed,
        public readonly ?int $receiptId = null,
        public readonly ?int $reversalId = null,
        public readonly array $errors = [],
        public readonly ?int $adjustmentId = null,
        /** @var array<string, int> Registro criado, por coluna (IdempotentOperations::REFS). */
        public readonly array $refs = [],
    ) {}

    public function ref(string $column): ?int
    {
        return $this->refs[$column] ?? null;
    }

    public function rejected(): bool
    {
        return $this->status === IdempotencyKey::REJECTED;
    }
}
