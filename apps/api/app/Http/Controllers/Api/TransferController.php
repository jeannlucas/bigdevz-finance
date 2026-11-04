<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Transfers\TransferFunds;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Api\Concerns\HandlesIdempotency;
use App\Http\Controllers\Controller;
use App\Http\Resources\TransferResource;
use App\Models\Transfer;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Validator;

class TransferController extends Controller
{
    use HandlesIdempotency;

    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        $space = $this->space($request, $space);
        $transfers = Transfer::query()
            ->where('space_id', $space->id)
            ->orderByDesc('transferred_at')
            ->orderByDesc('id')
            ->get();

        return TransferResource::collection($transfers);
    }

    public function store(
        Request $request,
        string $space,
        TransferFunds $transferFunds,
        IdempotentOperations $keys
    ): JsonResponse {
        $space = $this->space($request, $space);
        $key = $this->idempotencyKey($request);

        $rules = [
            'source_account_id' => ['required', 'integer'],
            'destination_account_id' => ['required', 'integer', 'different:source_account_id'],
            'amount' => ['required', new MoneyAmount(positive: true)],
            'transferred_at' => ['required', 'date_format:Y-m-d'],
            'notes' => ['nullable', 'string', 'max:500'],
        ];

        $messages = [
            'destination_account_id.different' => 'A conta de destino não pode ser a mesma conta de origem.',
        ];

        $validator = Validator::make($request->all(), $rules, $messages);

        if ($validator->fails()) {
            $fingerprint = TransferFunds::fingerprint(
                (int) $request->input('source_account_id'),
                (int) $request->input('destination_account_id'),
                $request->input('amount'),
                (string) $request->input('transferred_at'),
                $request->input('notes')
            );

            return $this->rejection($key, $keys->reject(
                $request->user(),
                $space,
                $key,
                IdempotentOperations::TRANSFER,
                $fingerprint,
                $validator->errors()->toArray()
            ));
        }

        $data = $validator->validated();

        // Validação de espaço e prevenção contra IDOR (404 Not Found)
        $space->accounts()->findOrFail($data['source_account_id']);
        $space->accounts()->findOrFail($data['destination_account_id']);

        $result = $transferFunds->handle(
            $request->user(),
            $space,
            (int) $data['source_account_id'],
            (int) $data['destination_account_id'],
            Money::toCents($data['amount']),
            $data['transferred_at'],
            $data['notes'] ?? null,
            $key
        );

        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }

        $transfer = Transfer::query()->where('space_id', $space->id)->findOrFail($result->ref('transfer_id'));

        return response()->json([
            'data' => (new TransferResource($transfer))->resolve(),
            'idempotency' => $this->idempotency($key, $result),
            'replayed' => $result->replayed,
        ], $result->replayed ? 200 : 201);
    }

    public function show(Request $request, string $space, string $transfer): JsonResponse
    {
        $space = $this->space($request, $space);
        $model = Transfer::query()->where('space_id', $space->id)->findOrFail($transfer);

        return (new TransferResource($model))->response();
    }
}
