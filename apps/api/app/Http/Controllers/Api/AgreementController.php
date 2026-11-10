<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\ChangeAgreements;
use App\Actions\Receivables\CreateAgreement;
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
            'open' => $query->whereNull('cancelled_at')->whereHas('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')),
            'overdue' => $query->whereNull('cancelled_at')->whereHas('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')->where('due_date', '<', $today)),
            'today' => $query->whereNull('cancelled_at')->whereHas('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')->where('due_date', '=', $today)),
            'next_30_days' => $query->whereNull('cancelled_at')->whereHas('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')->whereBetween('due_date', [$tomorrow, $in30Days])),
            'paid' => $query->whereNull('cancelled_at')->whereDoesntHave('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')),
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

    public function store(Request $request, string $space, CreateAgreement $createAgreement): JsonResponse
    {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), 'create_agreement');

        $data = $request->validate([
            'description' => ['required', 'string', 'max:120'],
            'total' => ['required', new MoneyAmount],
            'installment_count' => ['required', 'integer', 'between:1,1200'],
            'first_due_date' => ['required', 'date_format:Y-m-d'],
            'category_id' => ['nullable', 'integer'],
        ]);

        $space->ensureDateNotClosed($data['first_due_date'], 'criação de contrato');

        $agreement = $createAgreement->handle(
            $space,
            $data['description'],
            $data['total'],
            (int) $data['installment_count'],
            $data['first_due_date'],
            isset($data['category_id']) ? (int) $data['category_id'] : null,
        );

        return (new AgreementResource($agreement->load('installments')))->withInstallments()->response()->setStatusCode(201);
    }

    public function show(Request $request, string $space, string $agreement): AgreementResource
    {
        return (new AgreementResource(
            $this->space($request, $space)->agreements()->with(['installments', 'category'])->findOrFail($agreement),
        ))->withInstallments();
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
