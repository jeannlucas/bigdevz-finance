<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\ChangeAgreements;
use App\Actions\Receivables\CreateAgreement;
use App\Actions\Receivables\GenerateReceivables;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Controller;
use App\Http\Resources\AgreementResource;
use App\Rules\MoneyAmount;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Arr;
use Illuminate\Validation\Rule;

class AgreementController extends Controller
{
    private const STATUSES = ['all', 'open', 'overdue', 'today', 'next_30_days', 'paid', 'cancelled'];

    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        $data = $request->validate([
            'status' => ['nullable', Rule::in(self::STATUSES)],
            'category_id' => ['nullable', 'integer'],
        ]);
        $status = $data['status'] ?? 'open';

        $spaceModel = $this->space($request, $space);
        $today = Carbon::now(config('finance.timezone'))->toDateString();
        $tomorrow = Carbon::now(config('finance.timezone'))->addDay()->toDateString();
        $in30Days = Carbon::now(config('finance.timezone'))->addDays(30)->toDateString();

        $query = $spaceModel->agreements()->with(['installments', 'category'])->latest('id');

        if (! empty($data['category_id'])) {
            $query->where('category_id', $data['category_id']);
        }

        match ($status) {
            'open' => $query->whereNull('cancelled_at')->whereHas('installments', fn ($q) => $q->where(fn ($sub) => $sub->whereNull('amount_cents')->orWhereColumn('received_cents', '<', 'amount_cents'))),
            'overdue' => $query->whereNull('cancelled_at')->whereHas('installments', fn ($q) => $q->whereNotNull('amount_cents')->whereColumn('received_cents', '<', 'amount_cents')->where('due_date', '<', $today)),
            'today' => $query->whereNull('cancelled_at')->whereHas('installments', fn ($q) => $q->where(fn ($sub) => $sub->whereNull('amount_cents')->orWhereColumn('received_cents', '<', 'amount_cents'))->where('due_date', '=', $today)),
            'next_30_days' => $query->whereNull('cancelled_at')->whereHas('installments', fn ($q) => $q->where(fn ($sub) => $sub->whereNull('amount_cents')->orWhereColumn('received_cents', '<', 'amount_cents'))->whereBetween('due_date', [$tomorrow, $in30Days])),
            'paid' => $query->whereNull('cancelled_at')->whereDoesntHave('installments', fn ($q) => $q->whereNull('amount_cents')->orWhereColumn('received_cents', '<', 'amount_cents')),
            'cancelled' => $query->whereNotNull('cancelled_at'),
            default => null, // 'all'
        };

        $agreements = $query->get();
        $totalCount = $spaceModel->agreements()->count();

        return AgreementResource::collection($agreements)->additional([
            'meta' => [
                'status' => $status,
                'today' => $today,
                'total_count' => $totalCount,
            ],
        ]);
    }

    public function recurrencePreview(Request $request, string $space): JsonResponse
    {
        $this->space($request, $space);

        $data = $request->validate([
            'amount' => ['nullable', new MoneyAmount],
            'start_date' => ['required', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d', 'after:start_date'],
            'is_variable' => ['nullable', 'boolean'],
            'estimated_amount' => ['nullable', new MoneyAmount],
        ]);

        $today = GenerateReceivables::today();
        $horizon = GenerateReceivables::horizon();
        $until = min($data['end_date'] ?? $horizon, $horizon);
        $plan = GenerateReceivables::initialPlan($data['start_date'], $data['end_date'] ?? null, $until);
        $isVariable = filter_var($data['is_variable'] ?? false, FILTER_VALIDATE_BOOLEAN);
        $amount = isset($data['amount']) && $data['amount'] !== null ? Money::toCents($data['amount']) : 0;
        $estimated = isset($data['estimated_amount']) && $data['estimated_amount'] !== null ? Money::toCents($data['estimated_amount']) : 0;
        $checkCents = $isVariable ? ($amount > 0 ? $amount : $estimated) : $amount;
        $past = GenerateReceivables::pastOf($plan, $checkCents);

        return response()->json([
            'data' => [
                'reference_day' => (int) substr($data['start_date'], 8, 2),
                'end_date' => $data['end_date'] ?? null,
                'horizon' => $horizon,
                'approved_until' => $until,
                'first_due_date' => $plan[0]['due_date'],
                'last_due_date' => end($plan)['due_date'],
                'count' => count($plan),
                'past_count' => $past['count'],
                'past_total' => Money::formatAggregate($past['total_cents']),
                'total' => Money::formatAggregate($isVariable ? $amount : count($plan) * $amount),
                'is_variable' => $isVariable,
                'items' => array_map(static fn (array $cycle) => $cycle + [
                    'amount' => $isVariable
                        ? ($cycle['due_date'] === $data['start_date'] && $amount > 0 ? Money::fromCents($amount) : null)
                        : Money::fromCents($amount),
                    'past' => $cycle['due_date'] < $today,
                    'is_variable' => $isVariable,
                ], array_slice($plan, 0, 12)),
            ],
        ]);
    }

    public function store(Request $request, string $space, CreateAgreement $createAgreement): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $spaceModel->ensureCan($request->user(), 'create_agreement');

        $kind = $request->input('kind');
        $key = $request->header('Idempotency-Key');

        if ($key !== null) {
            $existing = $spaceModel->agreements()->where('idempotency_key', $key)->first();
            if ($existing !== null) {
                return (new AgreementResource($existing->load('installments', 'category')))->withInstallments()->response()->setStatusCode(200);
            }
        }

        if ($kind === 'recurring') {
            $data = $request->validate([
                'description' => ['required', 'string', 'max:120'],
                'is_variable' => ['nullable', 'boolean'],
                'amount' => [Rule::requiredIf(! $request->boolean('is_variable')), 'nullable', new MoneyAmount],
                'estimated_amount' => ['nullable', new MoneyAmount],
                'start_date' => ['required', 'date_format:Y-m-d'],
                'end_date' => ['nullable', 'date_format:Y-m-d', 'after:start_date'],
                'approved_until' => ['required', 'date_format:Y-m-d'],
                'confirm_past' => ['nullable', 'boolean'],
                'category_id' => ['nullable', 'integer'],
            ]);

            $spaceModel->ensureDateNotClosed($data['start_date'], 'criação de contrato recorrente');

            $agreement = $createAgreement->recurring(
                $request->user(),
                $spaceModel,
                $data,
                $key,
            );

            return (new AgreementResource($agreement->load('installments', 'category')))->withInstallments()->response()->setStatusCode(201);
        }

        $data = $request->validate([
            'description' => ['required', 'string', 'max:120'],
            'total' => ['required', new MoneyAmount],
            'installment_count' => ['required', 'integer', 'between:1,1200'],
            'first_due_date' => ['required', 'date_format:Y-m-d'],
            'category_id' => ['nullable', 'integer'],
        ]);

        $spaceModel->ensureDateNotClosed($data['first_due_date'], 'criação de contrato');

        $agreement = $createAgreement->handle(
            $spaceModel,
            $data['description'],
            $data['total'],
            (int) $data['installment_count'],
            $data['first_due_date'],
            isset($data['category_id']) ? (int) $data['category_id'] : null,
            $key,
        );

        return (new AgreementResource($agreement->load('installments', 'category')))->withInstallments()->response()->setStatusCode(201);
    }

    public function show(Request $request, string $space, string $agreement): AgreementResource
    {
        $item = $this->space($request, $space)->agreements()->with(['installments', 'category'])->findOrFail($agreement);
        if ($item->isRecurring()) {
            $item->load('installments.receipts.reversal', 'installments.receipts.correctionOf');
        }

        return (new AgreementResource($item))->withInstallments();
    }

    public function update(Request $request, string $space, string $agreement, ChangeAgreements $change): JsonResponse
    {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), 'edit_agreement');

        $existing = $space->agreements()->findOrFail($agreement);
        $space->ensureDateNotClosed($existing->first_due_date, 'edição de contrato');

        $data = $request->validate([
            'description' => ['sometimes', 'string', 'max:120'],
            'category_id' => ['nullable', 'integer'],
            'total' => ['sometimes', new MoneyAmount],
            'installment_count' => ['sometimes', 'integer', 'between:1,1200'],
            'first_due_date' => ['sometimes', 'date_format:Y-m-d'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        if (isset($data['first_due_date'])) {
            $space->ensureDateNotClosed($data['first_due_date'], 'edição de contrato');
        }

        $updated = $change->edit(
            $request->user(),
            $space,
            (int) $agreement,
            Arr::except($data, ['reason']),
            $data['reason'] ?? null,
        );

        return (new AgreementResource($updated->load(['installments', 'category'])))->withInstallments()->response();
    }

    public function cancel(Request $request, string $space, string $agreement, ChangeAgreements $change): JsonResponse
    {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), 'cancel_agreement');

        $existing = $space->agreements()->findOrFail($agreement);
        $space->ensureDateNotClosed($existing->first_due_date, 'cancelamento de contrato');

        $data = $request->validate([
            'reason' => ['required', 'string', 'max:500'],
        ]);
        $cancelled = $change->cancel($request->user(), $space, (int) $agreement, $data['reason']);

        return (new AgreementResource($cancelled->load(['installments', 'category'])))->withInstallments()->response();
    }
}
