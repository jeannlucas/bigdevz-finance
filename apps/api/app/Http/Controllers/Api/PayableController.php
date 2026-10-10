<?php

namespace App\Http\Controllers\Api;

use App\Actions\Payables\ChangeObligations;
use App\Actions\Payables\CreatePayable;
use App\Actions\Payables\GenerateObligations;
use App\Actions\Receivables\IdempotentOperations;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Api\Concerns\HandlesIdempotency;
use App\Http\Controllers\Controller;
use App\Http\Resources\PayableResource;
use App\Http\Resources\RecurrenceResource;
use App\Models\ObligationChange;
use App\Models\Payable;
use App\Models\PayablePlan;
use App\Models\Recurrence;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

/** Obrigações a pagar do espaço: lista, detalhe, cadastro, edição e cancelamento. */
class PayableController extends Controller
{
    use HandlesIdempotency;

    private const STATUSES = ['all', 'open', 'overdue', 'paid', 'cancelled', 'awaiting_amount'];

    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        $space = $this->space($request, $space);
        $status = $request->validate(['status' => ['nullable', Rule::in(self::STATUSES)]])['status'] ?? 'all';
        $today = GenerateObligations::today();
        $query = $space->payables()->with(['card', 'plan'])->orderBy('due_date')->orderBy('id');
        match ($status) {
            'open' => $query->whereNull('cancelled_at')->whereNotNull('amount_cents')->whereColumn('paid_cents', '<', 'amount_cents'),
            'overdue' => $query->whereNull('cancelled_at')->whereNotNull('amount_cents')->whereColumn('paid_cents', '<', 'amount_cents')->where('due_date', '<', $today),
            'paid' => $query->whereNull('cancelled_at')->whereColumn('paid_cents', '=', 'amount_cents'),
            'cancelled' => $query->whereNotNull('cancelled_at'),
            'awaiting_amount' => $query->whereNull('cancelled_at')->whereNull('amount_cents'),
            default => null,
        };

        return PayableResource::collection($query->get());
    }

    public function show(Request $request, string $space, string $payable): JsonResponse
    {
        $space = $this->space($request, $space);
        $model = $space->payables()->with(['card', 'plan', 'payments.reversal', 'payments.correctionOf'])->findOrFail($payable);

        return (new PayableResource($model))->additional(['changes' => $this->changes('payable', $model->id)])->response();
    }

    /** Prévia do cronograma parcelado, sem gravar (mesmo núcleo do cadastro). */
    public function preview(Request $request, string $space): JsonResponse
    {
        $this->space($request, $space);
        $data = $request->validate([
            'total' => ['required', new MoneyAmount],
            'installment_count' => ['required', 'integer', 'min:1', 'max:1200'],
            'first_due_date' => ['required', 'date_format:Y-m-d'],
        ]);

        return response()->json(['data' => CreatePayable::schedule($data['total'], (int) $data['installment_count'], $data['first_due_date'])]);
    }

    public function store(Request $request, string $space, CreatePayable $create, IdempotentOperations $keys): JsonResponse
    {
        $space = $this->space($request, $space);
        $key = $this->idempotencyKey($request);
        $kind = $request->input('kind');
        $common = ['description' => ['required', 'string', 'max:120'], 'payee' => ['nullable', 'string', 'max:120']];
        [$operation, $rules] = match ($kind) {
            'installment' => [IdempotentOperations::PAYABLE, $common + [
                'total' => ['required', new MoneyAmount],
                'installment_count' => ['required', 'integer', 'min:1', 'max:1200'],
                'first_due_date' => ['required', 'date_format:Y-m-d'],
            ]],
            'recurring' => [IdempotentOperations::RECURRENCE, $common + [
                'amount' => ['required', new MoneyAmount],
                'start_date' => ['required', 'date_format:Y-m-d'],
                'end_date' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:start_date'],
                // Período revisado na prévia: o conjunto criado é exatamente esse.
                'approved_until' => ['required', 'date_format:Y-m-d', 'regex:/-01$/'],
                'confirm_past' => ['required', 'boolean'],
            ]],
            default => [IdempotentOperations::PAYABLE, $common + [
                'kind' => ['required', Rule::in(['single', 'installment', 'recurring'])],
                'amount' => ['required', new MoneyAmount],
                'due_date' => ['required', 'date_format:Y-m-d'],
            ]],
        };
        $fields = array_values(array_diff(array_keys($rules), ['kind']));
        $raw = $request->only($fields) + ['kind' => $kind];
        $fingerprint = CreatePayable::fingerprint($operation, $space, $raw);
        $validator = Validator::make($request->all(), $rules);
        if ($validator->fails()) {
            return $this->rejection($key, $keys->reject($request->user(), $space, $key, $operation, $fingerprint, $validator->errors()->toArray()));
        }
        $data = $validator->validated();
        $result = match ($kind) {
            'installment' => $create->installments($request->user(), $space, $data, $key, $fingerprint),
            'recurring' => $create->recurrence($request->user(), $space, $data, $key, $fingerprint),
            default => $create->single($request->user(), $space, $data, $key, $fingerprint),
        };
        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }

        $payables = match (true) {
            $result->ref('payable_plan_id') !== null => PayablePlan::query()->findOrFail($result->ref('payable_plan_id'))->payables()->with('plan')->get(),
            // Conjunto inicial aprovado, mesmo num replay meses depois.
            $result->ref('recurrence_id') !== null => $this->initialOccurrences(Recurrence::query()->findOrFail($result->ref('recurrence_id'))),
            default => Payable::query()->whereKey($result->ref('payable_id'))->get(),
        };
        $recurrence = $result->ref('recurrence_id') === null ? null : Recurrence::query()->findOrFail($result->ref('recurrence_id'));

        return response()->json([
            'data' => [
                'kind' => $payables->first()?->kind ?? 'recurring',
                'payables' => PayableResource::collection($payables),
                'recurrence' => $recurrence === null ? null : new RecurrenceResource($recurrence),
                'replayed' => $result->replayed,
            ],
            'idempotency' => $this->idempotency($key, $result),
        ], $result->replayed ? 200 : 201);
    }

    /**
     * Prévia da recorrência, sem gravar: mesmas regras da geração, até o
     * horizonte atual. approved_until volta para o cadastro.
     */
    public function recurrencePreview(Request $request, string $space): JsonResponse
    {
        $this->space($request, $space);
        $data = $request->validate([
            'amount' => ['required', new MoneyAmount],
            'start_date' => ['required', 'date_format:Y-m-d'],
            'end_date' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:start_date'],
        ]);
        $horizon = GenerateObligations::horizon();
        $plan = CreatePayable::initialPlan($data['start_date'], $data['end_date'] ?? null, $horizon);
        $amount = Money::toCents($data['amount']);
        $past = CreatePayable::pastOf($plan, $amount);
        $today = GenerateObligations::today();

        return response()->json(['data' => [
            'start_date' => $data['start_date'],
            'reference_day' => (int) substr($data['start_date'], 8, 2),
            'end_date' => $data['end_date'] ?? null,
            'today' => $today,
            'horizon' => $horizon,
            'approved_until' => end($plan)['cycle'],
            'first_due_date' => $plan[0]['due_date'],
            'last_due_date' => end($plan)['due_date'],
            'count' => count($plan),
            'past_count' => $past['count'],
            'past_total' => Money::fromCents($past['total_cents']),
            'total' => Money::fromCents(count($plan) * $amount),
            'items' => array_map(static fn (array $cycle) => $cycle + ['amount' => Money::fromCents($amount), 'past' => $cycle['due_date'] < $today],
                array_slice($plan, 0, CreatePayable::PREVIEW_ITEMS)),
            'items_shown' => min(count($plan), CreatePayable::PREVIEW_ITEMS),
        ]]);
    }

    /** Esta obrigação (ou ocorrência). Em fatura, informa/corrige o total. */
    public function update(Request $request, string $space, string $payable, ChangeObligations $change): JsonResponse
    {
        $space = $this->space($request, $space);
        $model = $space->payables()->findOrFail($payable);
        $data = $request->validate([
            'description' => ['sometimes', 'required', 'string', 'max:120'],
            'payee' => ['sometimes', 'nullable', 'string', 'max:120'],
            'amount' => ['sometimes', 'nullable', new MoneyAmount],
            'due_date' => ['sometimes', 'required', 'date_format:Y-m-d'],
            'reason' => ['nullable', 'string', 'max:500'],
            'space_id' => ['prohibited'],
        ], ['space_id.prohibited' => 'A obrigação não pode mudar de espaço.']);
        $reason = $data['reason'] ?? null;
        unset($data['reason']);
        $updated = $change->edit($request->user(), $space, $model->id, $data, $reason);

        return $this->show($request, (string) $space->id, (string) $updated->id);
    }

    public function cancel(Request $request, string $space, string $payable, ChangeObligations $change): JsonResponse
    {
        $space = $this->space($request, $space);
        $model = $space->payables()->findOrFail($payable);
        $data = $request->validate(['reason' => ['required', 'string', 'min:3', 'max:500']], [
            'reason.required' => 'Informe o motivo.',
        ]);
        $change->cancel($request->user(), $space, $model->id, $data['reason']);

        return $this->show($request, (string) $space->id, (string) $model->id);
    }

    private function initialOccurrences(Recurrence $recurrence)
    {
        $query = $recurrence->occurrences()->getQuery();
        if ($recurrence->initial_until !== null) {
            $query->where('cycle', '<=', $recurrence->initial_until->toDateString());
        }

        return $query->get();
    }

    private function changes(string $subject, int $id): array
    {
        return ObligationChange::query()->where('subject', $subject)->where('subject_id', $id)->orderByDesc('id')->get()
            ->map(fn (ObligationChange $change) => [
                'action' => $change->action, 'before' => $change->before, 'after' => $change->after,
                'reason' => $change->reason, 'user_id' => $change->user_id, 'changed_at' => $change->created_at?->toIso8601String(),
            ])->all();
    }
}
