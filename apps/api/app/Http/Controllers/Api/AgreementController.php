<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\CreateAgreement;
use App\Http\Controllers\Controller;
use App\Http\Resources\AgreementResource;
use App\Rules\MoneyAmount;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

class AgreementController extends Controller
{
    private const STATUSES = ['all', 'open', 'overdue', 'today', 'next_30_days', 'paid'];

    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        $status = $request->validate([
            'status' => ['nullable', Rule::in(self::STATUSES)],
        ])['status'] ?? 'open';

        $spaceModel = $this->space($request, $space);
        $today = Carbon::now(config('finance.timezone'))->toDateString();
        $tomorrow = Carbon::now(config('finance.timezone'))->addDay()->toDateString();
        $in30Days = Carbon::now(config('finance.timezone'))->addDays(30)->toDateString();

        $query = $spaceModel->agreements()->with('installments')->latest('id');

        match ($status) {
            'open' => $query->whereHas('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')),
            'overdue' => $query->whereHas('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')->where('due_date', '<', $today)),
            'today' => $query->whereHas('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')->where('due_date', '=', $today)),
            'next_30_days' => $query->whereHas('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')->whereBetween('due_date', [$tomorrow, $in30Days])),
            'paid' => $query->whereDoesntHave('installments', fn ($q) => $q->whereColumn('received_cents', '<', 'amount_cents')),
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
        $data = $request->validate([
            'description' => ['required', 'string', 'max:120'],
            'total' => ['required', new MoneyAmount],
            'installment_count' => ['required', 'integer', 'between:1,1200'],
            'first_due_date' => ['required', 'date_format:Y-m-d'],
        ]);

        $agreement = $createAgreement->handle(
            $space, $data['description'], $data['total'], (int) $data['installment_count'], $data['first_due_date'],
        );

        return (new AgreementResource($agreement->load('installments')))->withInstallments()->response()->setStatusCode(201);
    }

    public function show(Request $request, string $space, string $agreement): AgreementResource
    {
        return (new AgreementResource(
            $this->space($request, $space)->agreements()->with('installments')->findOrFail($agreement),
        ))->withInstallments();
    }
}
