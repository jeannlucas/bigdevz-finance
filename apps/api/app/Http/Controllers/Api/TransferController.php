<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Transfers\ReverseTransfer;
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
            ->where(function ($q) use ($space) {
                $q->where('space_id', $space->id)
                    ->orWhere('destination_space_id', $space->id);
            })
            ->with([
                'reversal',
                'sourceAccount',
                'destinationAccount',
                'space',
                'destinationSpace',
            ])
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
        $space->ensureCan($request->user(), 'transfer_funds');
        if ($request->filled('transferred_at')) {
            $space->ensureDateNotClosed($request->input('transferred_at'), 'transferência entre contas');
        }

        $destinationSpaceId = $request->input('destination_space_id');
        $destinationSpace = $destinationSpaceId !== null
            ? $request->user()->spaces()->findOrFail($destinationSpaceId)
            : $space;

        $key = $this->idempotencyKey($request);

        $rules = [
            'source_account_id' => ['required', 'integer'],
            'destination_space_id' => ['nullable', 'integer'],
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
                $request->input('notes'),
                $space->id,
                $destinationSpace->id
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
        $destinationSpace->accounts()->findOrFail($data['destination_account_id']);

        $result = $transferFunds->handle(
            $request->user(),
            $space,
            (int) $data['source_account_id'],
            (int) $data['destination_account_id'],
            Money::toCents($data['amount']),
            $data['transferred_at'],
            $data['notes'] ?? null,
            $key,
            $destinationSpace
        );

        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }

        $transfer = Transfer::query()
            ->where(function ($q) use ($space) {
                $q->where('space_id', $space->id)
                    ->orWhere('destination_space_id', $space->id);
            })
            ->with(['reversal', 'sourceAccount', 'destinationAccount', 'space', 'destinationSpace'])
            ->findOrFail($result->ref('transfer_id'));

        return response()->json([
            'data' => (new TransferResource($transfer))->resolve(),
            'idempotency' => $this->idempotency($key, $result),
            'replayed' => $result->replayed,
        ], $result->replayed ? 200 : 201);
    }

    public function show(Request $request, string $space, string $transfer): JsonResponse
    {
        $space = $this->space($request, $space);
        $model = Transfer::query()
            ->where(function ($q) use ($space) {
                $q->where('space_id', $space->id)
                    ->orWhere('destination_space_id', $space->id);
            })
            ->with(['reversal', 'sourceAccount', 'destinationAccount', 'space', 'destinationSpace'])
            ->findOrFail($transfer);

        return (new TransferResource($model))->response();
    }

    public function reverse(
        Request $request,
        string $space,
        string $transfer,
        ReverseTransfer $reverseTransfer,
        IdempotentOperations $keys
    ): JsonResponse {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), 'reverse_transfer');

        $transferModel = Transfer::query()
            ->where(function ($q) use ($space) {
                $q->where('space_id', $space->id)
                    ->orWhere('destination_space_id', $space->id);
            })
            ->findOrFail($transfer);

        $key = $this->idempotencyKey($request);

        $rules = [
            'reason' => ['required', 'string', 'min:3', 'max:500'],
        ];

        $validator = Validator::make($request->all(), $rules);

        if ($validator->fails()) {
            $fingerprint = ReverseTransfer::fingerprint(
                $transferModel->id,
                $request->input('reason')
            );

            return $this->rejection($key, $keys->reject(
                $request->user(),
                $space,
                $key,
                IdempotentOperations::TRANSFER_REVERSAL,
                $fingerprint,
                $validator->errors()->toArray()
            ));
        }

        $data = $validator->validated();

        $result = $reverseTransfer->handle(
            $request->user(),
            $space,
            $transferModel->id,
            $data['reason'],
            $key
        );

        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }

        $transferModel->refresh()->load(['reversal', 'sourceAccount', 'destinationAccount', 'space', 'destinationSpace']);

        return response()->json([
            'data' => (new TransferResource($transferModel))->resolve(),
            'idempotency' => $this->idempotency($key, $result),
            'replayed' => $result->replayed,
        ], $result->replayed ? 200 : 201);
    }
}
