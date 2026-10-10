<?php

namespace App\Actions\Receivables;

use App\Models\IdempotencyKey;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\User;
use Closure;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Executa cada chave idempotente do espaço no máximo uma vez e guarda a
 * decisão final: concluída (com o registro criado) ou recusada (com os
 * erros). Repetir a chave com o mesmo conteúdo devolve essa decisão, mesmo
 * que as condições financeiras tenham mudado depois (um estorno reabrindo a
 * parcela, por exemplo); conteúdo diferente é conflito.
 *
 * Requisições com a mesma chave são serializadas por um lock consultivo do
 * PostgreSQL, tomado antes de qualquer outro lock. A decisão é gravada na
 * mesma transação do efeito: se algo falhar, nem efeito nem decisão ficam.
 */
class IdempotentOperations
{
    public const RECEIPT = 'receipt';

    public const REVERSAL = 'reversal';

    public const CORRECTION = 'correction';

    public const OPENING_ADJUSTMENT = 'opening_adjustment';

    public const PAYABLE = 'payable';

    public const RECURRENCE = 'recurrence';

    public const PAYMENT = 'payment';

    public const PAYMENT_REVERSAL = 'payment_reversal';

    public const PAYMENT_CORRECTION = 'payment_correction';

    /** Colunas que apontam o registro criado por uma chave concluída. */
    public const REFS = [
        'receipt_id', 'receipt_reversal_id', 'account_opening_adjustment_id',
        'payable_id', 'payable_plan_id', 'recurrence_id', 'payment_id', 'payment_reversal_id',
    ];

    /** Impressão do conteúdo: operação, alvo (parcela ou recebimento) e campos. */
    public static function fingerprint(string $operation, int $target, array $fields): string
    {
        return hash('sha256', $operation.'|'.$target.'|'.json_encode($fields, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    /**
     * O trabalho trava, valida (ValidationException é recusa) e grava. Roda
     * num savepoint: uma recusa não deixa escrita parcial.
     *
     * @param  Closure(): array<string, int>  $work  Uma das colunas de REFS e o id criado.
     * @param  string|null  $legacyFingerprint  Formato anterior a esta tabela,
     *                                          para recebimentos antigos.
     */
    public function run(
        User $user,
        Space $space,
        string $key,
        string $operation,
        string $fingerprint,
        Closure $work,
        ?string $legacyFingerprint = null,
    ): KeyedResult {
        return DB::transaction(function () use ($user, $space, $key, $operation, $fingerprint, $work, $legacyFingerprint) {
            $this->lock($space, $key);
            if ($decided = $this->decision($space, $key, $operation, $fingerprint, $legacyFingerprint)) {
                return $decided;
            }
            try {
                $refs = DB::transaction($work);
            } catch (ValidationException $error) {
                return $this->store($user, $space, $key, $operation, $fingerprint, errors: $error->errors());
            }

            return $this->store($user, $space, $key, $operation, $fingerprint, refs: $refs);
        });
    }

    /** Recusa do pedido (formato, data futura...) também fica vinculada à chave. */
    public function reject(User $user, Space $space, string $key, string $operation, string $fingerprint, array $errors): KeyedResult
    {
        return DB::transaction(function () use ($user, $space, $key, $operation, $fingerprint, $errors) {
            $this->lock($space, $key);

            return $this->decision($space, $key, $operation, $fingerprint, null)
                ?? $this->store($user, $space, $key, $operation, $fingerprint, errors: $errors);
        });
    }

    private function lock(Space $space, string $key): void
    {
        DB::select('SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', ["idempotency:{$space->id}:{$key}"]);
    }

    private function decision(Space $space, string $key, string $operation, string $fingerprint, ?string $legacyFingerprint): ?KeyedResult
    {
        $record = IdempotencyKey::query()->where('space_id', $space->id)->where('key', $key)->first();
        if ($record !== null) {
            if ($record->operation !== $operation || ! hash_equals($record->fingerprint, $fingerprint)) {
                throw new IdempotencyConflict;
            }

            return new KeyedResult($record->status, true, $record->receipt_id, $record->receipt_reversal_id, $record->errors ?? [], $record->account_opening_adjustment_id, $this->refs($record));
        }

        // Recebimentos gravados antes desta tabela guardam a chave no próprio registro.
        $legacy = Receipt::query()->where('space_id', $space->id)->where('idempotency_key', $key)->first();
        if ($legacy === null) {
            return null;
        }
        $same = $operation === self::RECEIPT && (hash_equals($legacy->request_fingerprint, $fingerprint)
            || ($legacyFingerprint !== null && hash_equals($legacy->request_fingerprint, $legacyFingerprint)));
        if (! $same) {
            throw new IdempotencyConflict;
        }

        return new KeyedResult(IdempotencyKey::COMPLETED, true, receiptId: $legacy->id);
    }

    /** @return array<string, int> */
    private function refs(IdempotencyKey $record): array
    {
        return array_filter($record->only(self::REFS), static fn ($id) => $id !== null);
    }

    /** @param array<string, int> $refs */
    private function store(User $user, Space $space, string $key, string $operation, string $fingerprint, array $refs = [], ?array $errors = null): KeyedResult
    {
        $record = IdempotencyKey::create([
            'space_id' => $space->id,
            'user_id' => $user->id,
            'key' => $key,
            'operation' => $operation,
            'fingerprint' => $fingerprint,
            'status' => $errors === null ? IdempotencyKey::COMPLETED : IdempotencyKey::REJECTED,
            'errors' => $errors,
            ...array_intersect_key($refs, array_flip(self::REFS)),
        ]);

        return new KeyedResult($record->status, false, $record->receipt_id, $record->receipt_reversal_id, $errors ?? [], $record->account_opening_adjustment_id, $this->refs($record));
    }
}
