<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\StatementResource;
use App\Models\Account;
use App\Models\AccountMovement;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class StatementController extends Controller
{
    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        $space = $this->space($request, $space);

        $request->validate([
            'account_id' => ['nullable', 'integer'],
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d'],
            'direction' => ['nullable', 'in:credit,debit'],
            'category_id' => ['nullable', 'integer'],
        ]);

        if ($request->filled('account_id')) {
            Account::query()
                ->where('space_id', $space->id)
                ->findOrFail($request->integer('account_id'));
        }

        $query = AccountMovement::query()
            ->whereHas('account', fn ($q) => $q->where('space_id', $space->id))
            ->with([
                'account',
                'category',
                'receipt.installment.agreement.category',
                'receiptReversal',
                'payment.payable.category',
                'paymentReversal',
                'transfer.sourceAccount',
                'transfer.destinationAccount',
                'loanDisbursement',
            ]);

        if ($request->filled('account_id')) {
            $query->where('account_id', $request->integer('account_id'));
        }

        if ($request->filled('category_id')) {
            $catId = $request->integer('category_id');
            $query->where(function ($q) use ($catId) {
                $q->where('category_id', $catId)
                    ->orWhereHas('payment.payable', fn ($pq) => $pq->where('category_id', $catId))
                    ->orWhereHas('receipt.installment.agreement', fn ($aq) => $aq->where('category_id', $catId));
            });
        }

        if ($request->filled('from')) {
            $query->where('effective_date', '>=', $request->query('from'));
        }

        if ($request->filled('to')) {
            $query->where('effective_date', '<=', $request->query('to'));
        }

        if ($request->filled('direction')) {
            $direction = $request->query('direction');
            if ($direction === 'credit') {
                $query->where('amount_cents', '>', 0);
            } elseif ($direction === 'debit') {
                $query->where('amount_cents', '<', 0);
            }
        }

        $movements = $query
            ->orderByDesc('effective_date')
            ->orderByDesc('id')
            ->limit(500)
            ->get();

        return StatementResource::collection($movements);
    }
}
