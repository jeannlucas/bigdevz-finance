<?php

namespace App\Http\Controllers\Api;

use App\Actions\Loans\CreateLoan;
use App\Actions\Receivables\IdempotentOperations;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Api\Concerns\HandlesIdempotency;
use App\Http\Controllers\Controller;
use App\Http\Resources\LoanResource;
use App\Models\Loan;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

class LoanController extends Controller
{
    use HandlesIdempotency;

    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        $space = $this->space($request, $space);

        $query = Loan::query()
            ->where('space_id', $space->id)
            ->with(['payablePlan.payables', 'agreement.installments'])
            ->orderByDesc('id');

        if ($kind = $request->input('kind')) {
            if (in_array($kind, [Loan::KIND_TAKEN, Loan::KIND_GRANTED], true)) {
                $query->where('kind', $kind);
            }
        }

        $loans = $query->get();

        if ($status = $request->input('status')) {
            if ($status === 'active') {
                $loans = $loans->filter(fn (Loan $l) => $l->computedStatus() === 'active')->values();
            } elseif ($status === 'settled') {
                $loans = $loans->filter(fn (Loan $l) => $l->computedStatus() === 'settled')->values();
            }
        }

        return LoanResource::collection($loans);
    }

    public function show(Request $request, string $space, int $loan): LoanResource
    {
        $space = $this->space($request, $space);

        $loanModel = Loan::query()
            ->where('space_id', $space->id)
            ->with(['payablePlan.payables', 'agreement.installments'])
            ->findOrFail($loan);

        return (new LoanResource($loanModel))->withInstallments();
    }

    public function store(
        Request $request,
        string $space,
        CreateLoan $createLoan,
        IdempotentOperations $keys
    ): JsonResponse {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), 'create_loan');
        if ($request->filled('first_due_date')) {
            $space->ensureDateNotClosed($request->input('first_due_date'), 'empréstimo');
        }

        $key = $this->idempotencyKey($request);

        $rules = [
            'kind' => ['required', 'string', Rule::in([Loan::KIND_TAKEN, Loan::KIND_GRANTED])],
            'title' => ['required', 'string', 'max:120'],
            'counterparty' => ['required', 'string', 'max:120'],
            'principal' => ['required', new MoneyAmount(positive: true)],
            'total' => ['required', new MoneyAmount(positive: true)],
            'installment_count' => ['required', 'integer', 'between:1,1200'],
            'first_due_date' => ['required', 'date_format:Y-m-d'],
            'disbursement_account_id' => ['nullable', 'integer'],
            'disbursed_at' => ['nullable', 'date_format:Y-m-d'],
            'notes' => ['nullable', 'string', 'max:500'],
        ];

        $validator = Validator::make($request->all(), $rules);

        $fingerprint = CreateLoan::fingerprint(
            (string) $request->input('kind'),
            $request->input('principal'),
            $request->input('total'),
            (int) $request->input('installment_count'),
            (string) $request->input('first_due_date'),
            $request->input('disbursement_account_id') ? (int) $request->input('disbursement_account_id') : null,
            $request->input('disbursed_at') ? (string) $request->input('disbursed_at') : null,
            (string) $request->input('title'),
            (string) $request->input('counterparty'),
            $request->input('notes')
        );

        if ($validator->fails()) {
            return $this->rejection($key, $keys->reject(
                $request->user(),
                $space,
                $key,
                IdempotentOperations::LOAN,
                $fingerprint,
                $validator->errors()->toArray()
            ));
        }

        $data = $validator->validated();

        $principalCents = Money::toCents($data['principal']);
        $totalCents = Money::toCents($data['total']);

        if ($totalCents < $principalCents) {
            return $this->rejection($key, $keys->reject(
                $request->user(),
                $space,
                $key,
                IdempotentOperations::LOAN,
                $fingerprint,
                ['total' => ['O valor total com juros/encargos não pode ser menor que o valor principal.']]
            ));
        }

        if (! empty($data['disbursement_account_id'])) {
            $space->accounts()->findOrFail($data['disbursement_account_id']);
        }

        $result = $createLoan->handle(
            $request->user(),
            $space,
            $data['kind'],
            $data['title'],
            $data['counterparty'],
            $principalCents,
            $totalCents,
            (int) $data['installment_count'],
            $data['first_due_date'],
            ! empty($data['disbursement_account_id']) ? (int) $data['disbursement_account_id'] : null,
            $data['disbursed_at'] ?? null,
            $data['notes'] ?? null,
            $key
        );

        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }

        $loan = Loan::query()
            ->where('space_id', $space->id)
            ->with(['payablePlan.payables', 'agreement.installments'])
            ->findOrFail($result->ref('loan_id'));

        return response()->json([
            'data' => (new LoanResource($loan))->resolve(),
            'idempotency' => $this->idempotency($key, $result),
            'replayed' => $result->replayed,
        ], $result->replayed ? 200 : 201);
    }
}
