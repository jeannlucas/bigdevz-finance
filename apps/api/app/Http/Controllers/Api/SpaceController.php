<?php

namespace App\Http\Controllers\Api;

use App\Domain\Receivables\Money;
use App\Http\Controllers\Controller;
use App\Http\Resources\SpaceResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class SpaceController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        return SpaceResource::collection($request->user()->spaces);
    }

    /** Saldo efetivado e valores a receber do espaço; previsões não somam ao saldo. */
    public function summary(Request $request, string $space): JsonResponse
    {
        $space = $this->space($request, $space);
        $accounts = $space->accounts()->withSum('movements', 'amount_cents')->get();
        $installments = $space->installments()->get();

        return response()->json(['data' => [
            'space' => new SpaceResource($space),
            'balance' => Money::fromCents($accounts->sum(fn ($account) => $account->balanceCents())),
            'accounts_count' => $accounts->count(),
            'agreements_count' => $space->agreements()->count(),
            'received_total' => Money::fromCents($installments->sum('received_cents')),
            'receivable_remaining' => Money::fromCents($installments->sum(fn ($item) => $item->remainingCents())),
            'overdue_installments' => $installments->filter(fn ($item) => $item->isOverdue())->count(),
        ]]);
    }
}
