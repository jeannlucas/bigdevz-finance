<?php

namespace App\Http\Controllers\Api\Concerns;

use App\Actions\Receivables\KeyedResult;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

/**
 * Cabeçalho Idempotency-Key e respostas com a decisão da chave. Toda
 * resposta de operação com chave válida informa `idempotency.status`; só
 * `rejected` persistido prova que aquela chave nunca produzirá efeito.
 */
trait HandlesIdempotency
{
    /** Sem chave válida nada é registrado: o 422 sai sem `idempotency`. */
    protected function idempotencyKey(Request $request): string
    {
        $key = $request->header('Idempotency-Key');
        Validator::make(['idempotency_key' => $key], [
            'idempotency_key' => ['required', 'string', 'min:1', 'max:100'],
        ], [
            'idempotency_key.required' => 'Envie o cabeçalho Idempotency-Key para esta operação.',
        ])->validate();

        return $key;
    }

    /** @return array{key: string, status: string, replayed: bool} */
    protected function idempotency(string $key, KeyedResult $result): array
    {
        return ['key' => $key, 'status' => $result->status, 'replayed' => $result->replayed];
    }

    protected function rejection(string $key, KeyedResult $result): JsonResponse
    {
        return response()->json([
            'message' => collect($result->errors)->flatten()->first() ?? 'Operação recusada.',
            'errors' => $result->errors,
            'idempotency' => $this->idempotency($key, $result),
        ], 422);
    }
}
