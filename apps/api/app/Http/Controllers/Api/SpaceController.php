<?php

namespace App\Http\Controllers\Api;

use App\Actions\Payables\GenerateObligations;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Controller;
use App\Http\Resources\SpaceResource;
use App\Models\Space;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Carbon;

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
            // O saldo inclui contas arquivadas: arquivar não zera nem transfere dinheiro.
            'accounts_count' => $accounts->count(),
            'active_accounts_count' => $accounts->filter(fn ($account) => ! $account->isArchived())->count(),
            'archived_accounts_count' => $accounts->filter(fn ($account) => $account->isArchived())->count(),
            'agreements_count' => $space->agreements()->count(),
            'received_total' => Money::fromCents($installments->sum('received_cents')),
            'receivable_remaining' => Money::fromCents($installments->sum(fn ($item) => $item->remainingCents())),
            'overdue_installments' => $installments->filter(fn ($item) => $item->isOverdue())->count(),
            // A pagar: previsto, separado do saldo (obrigação não reduz saldo).
            'payables' => $this->payables($space),
        ]]);
    }

    /**
     * Restantes de obrigações não canceladas com valor; faturas sem total
     * contam à parte. "Próximos 30 dias" inclui hoje. Pago líquido é o
     * realizado (pagamentos menos estornos), de todas as obrigações.
     */
    private function payables(Space $space): array
    {
        $today = GenerateObligations::today();
        $until = Carbon::parse($today)->addDays(30)->toDateString();
        $open = $space->payables()->whereNull('cancelled_at')->whereNotNull('amount_cents')->whereColumn('paid_cents', '<', 'amount_cents');
        $remaining = 'COALESCE(SUM(amount_cents - paid_cents), 0)';

        return [
            'open_total' => Money::fromCents((int) (clone $open)->selectRaw($remaining.' AS total')->value('total')),
            'open_count' => (clone $open)->count(),
            'overdue_total' => Money::fromCents((int) (clone $open)->where('due_date', '<', $today)->selectRaw($remaining.' AS total')->value('total')),
            'overdue_count' => (clone $open)->where('due_date', '<', $today)->count(),
            'due_next_30_days_total' => Money::fromCents((int) (clone $open)->whereBetween('due_date', [$today, $until])->selectRaw($remaining.' AS total')->value('total')),
            'paid_total' => Money::fromCents((int) $space->payables()->sum('paid_cents')),
            'awaiting_amount_count' => $space->payables()->whereNull('cancelled_at')->whereNull('amount_cents')->count(),
            'today' => $today,
        ];
    }
}
