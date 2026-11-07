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
use Illuminate\Support\Facades\DB;

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
            'balance' => Money::sum($accounts->map(fn ($account) => $account->balanceCents())),
            // O saldo inclui contas arquivadas: arquivar não zera nem transfere dinheiro.
            'accounts_count' => $accounts->count(),
            'active_accounts_count' => $accounts->filter(fn ($account) => ! $account->isArchived())->count(),
            'archived_accounts_count' => $accounts->filter(fn ($account) => $account->isArchived())->count(),
            'agreements_count' => $space->agreements()->count(),
            'received_total' => Money::sum($installments->pluck('received_cents')),
            'receivable_remaining' => Money::sum($installments->map(fn ($item) => $item->remainingCents())),
            'overdue_installments' => $installments->filter(fn ($item) => $item->isOverdue())->count(),
            // A pagar: previsto, separado do saldo (obrigação não reduz saldo).
            'payables' => $this->payables($space),
            'categories_summary' => [
                'expenses' => $this->expenseCategoriesSummary($space),
                'incomes' => $this->incomeCategoriesSummary($space),
            ],
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
            'open_total' => Money::formatAggregate((clone $open)->selectRaw($remaining.' AS total')->value('total')),
            'open_count' => (clone $open)->count(),
            'overdue_total' => Money::formatAggregate((clone $open)->where('due_date', '<', $today)->selectRaw($remaining.' AS total')->value('total')),
            'overdue_count' => (clone $open)->where('due_date', '<', $today)->count(),
            'due_next_30_days_total' => Money::formatAggregate((clone $open)->whereBetween('due_date', [$today, $until])->selectRaw($remaining.' AS total')->value('total')),
            'paid_total' => Money::sum($space->payables()->pluck('paid_cents')),
            'awaiting_amount_count' => $space->payables()->whereNull('cancelled_at')->whereNull('amount_cents')->count(),
            'today' => $today,
        ];
    }

    private function expenseCategoriesSummary(Space $space): array
    {
        return DB::table('payables')
            ->leftJoin('categories', 'payables.category_id', '=', 'categories.id')
            ->where('payables.space_id', $space->id)
            ->whereNull('payables.cancelled_at')
            ->whereNotNull('payables.amount_cents')
            ->select(
                DB::raw('COALESCE(categories.id, 0) as id'),
                DB::raw("COALESCE(categories.name, 'Outros / Sem categoria') as name"),
                DB::raw("COALESCE(categories.icon, 'category') as icon"),
                DB::raw("COALESCE(categories.color, '#6B7280') as color"),
                DB::raw('COALESCE(SUM(payables.amount_cents), 0) as total_cents')
            )
            ->groupBy(
                DB::raw('COALESCE(categories.id, 0)'),
                DB::raw("COALESCE(categories.name, 'Outros / Sem categoria')"),
                DB::raw("COALESCE(categories.icon, 'category')"),
                DB::raw("COALESCE(categories.color, '#6B7280')")
            )
            ->havingRaw('COALESCE(SUM(payables.amount_cents), 0) > 0')
            ->orderByDesc('total_cents')
            ->get()
            ->map(fn ($row) => [
                'id' => (int) $row->id,
                'name' => $row->name,
                'icon' => $row->icon,
                'color' => $row->color,
                'total' => Money::formatAggregate((int) $row->total_cents),
                'total_cents' => (int) $row->total_cents,
            ])
            ->values()
            ->all();
    }

    private function incomeCategoriesSummary(Space $space): array
    {
        return DB::table('agreements')
            ->leftJoin('categories', 'agreements.category_id', '=', 'categories.id')
            ->where('agreements.space_id', $space->id)
            ->select(
                DB::raw('COALESCE(categories.id, 0) as id'),
                DB::raw("COALESCE(categories.name, 'Outros / Sem categoria') as name"),
                DB::raw("COALESCE(categories.icon, 'category') as icon"),
                DB::raw("COALESCE(categories.color, '#6B7280') as color"),
                DB::raw('COALESCE(SUM(agreements.total_cents), 0) as total_cents')
            )
            ->groupBy(
                DB::raw('COALESCE(categories.id, 0)'),
                DB::raw("COALESCE(categories.name, 'Outros / Sem categoria')"),
                DB::raw("COALESCE(categories.icon, 'category')"),
                DB::raw("COALESCE(categories.color, '#6B7280')")
            )
            ->havingRaw('COALESCE(SUM(agreements.total_cents), 0) > 0')
            ->orderByDesc('total_cents')
            ->get()
            ->map(fn ($row) => [
                'id' => (int) $row->id,
                'name' => $row->name,
                'icon' => $row->icon,
                'color' => $row->color,
                'total' => Money::formatAggregate((int) $row->total_cents),
                'total_cents' => (int) $row->total_cents,
            ])
            ->values()
            ->all();
    }
}
