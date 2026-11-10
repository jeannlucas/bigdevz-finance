<?php

namespace App\Http\Controllers\Api;

use App\Domain\Receivables\Money;
use App\Http\Controllers\Controller;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Installment;
use App\Models\Payable;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;

class CashFlowController extends Controller
{
    public function index(Request $request, string $space): JsonResponse|StreamedResponse
    {
        $spaceModel = $this->space($request, $space);

        if ($request->boolean('export')) {
            $spaceModel->ensureCan($request->user(), 'export_data');
        }

        $request->validate([
            'days' => ['nullable', 'in:30,60,90'],
            'start_date' => ['nullable', 'date_format:Y-m-d'],
            'account_id' => ['nullable', 'integer'],
            'category_id' => ['nullable', 'integer'],
            'view' => ['nullable', 'in:cash,accrual'],
        ]);

        $days = $request->integer('days', 30);
        $view = $request->query('view', 'cash');
        $tz = config('finance.timezone', 'America/Sao_Paulo');
        $startDateStr = $request->query('start_date') ?? now($tz)->toDateString();
        $startDate = Carbon::parse($startDateStr, $tz)->startOfDay();
        $endDate = $startDate->copy()->addDays($days - 1)->endOfDay();
        $endDateStr = $endDate->toDateString();

        $accountId = $request->filled('account_id') ? $request->integer('account_id') : null;
        $categoryId = $request->filled('category_id') ? $request->integer('category_id') : null;

        if ($accountId !== null) {
            Account::query()->where('space_id', $spaceModel->id)->findOrFail($accountId);
        }

        // 1. Saldo Inicial consolidado antes de $startDateStr
        $initialBalanceCents = $this->calculateInitialBalance($spaceModel->id, $startDateStr, $accountId);

        // 2. Movimentos Realizados no período
        $movementsQuery = AccountMovement::query()
            ->whereHas('account', fn ($q) => $q->where('space_id', $spaceModel->id))
            ->whereBetween('effective_date', [$startDateStr, $endDateStr]);

        if ($accountId !== null) {
            $movementsQuery->where('account_id', $accountId);
        }
        if ($categoryId !== null) {
            $movementsQuery->where(function ($q) use ($categoryId) {
                $q->where('category_id', $categoryId)
                    ->orWhereHas('payment.payable', fn ($pq) => $pq->where('category_id', $categoryId))
                    ->orWhereHas('receipt.installment.agreement', fn ($aq) => $aq->where('category_id', $categoryId));
            });
        }
        $movements = $movementsQuery->get();

        // 3. Entradas Previstas (Parcelas de Acordos em aberto e não cancelados)
        $installmentsQuery = Installment::query()
            ->where('space_id', $spaceModel->id)
            ->whereRaw('received_cents < amount_cents')
            ->whereHas('agreement', fn ($q) => $q->whereNull('cancelled_at'));

        $dueDateField = $view === 'accrual' ? 'created_at' : 'due_date';
        if ($view === 'accrual') {
            $installmentsQuery->whereBetween('created_at', [$startDate, $endDate]);
        } else {
            $installmentsQuery->whereBetween('due_date', [$startDateStr, $endDateStr]);
        }

        if ($categoryId !== null) {
            $installmentsQuery->whereHas('agreement', fn ($q) => $q->where('category_id', $categoryId));
        }
        $pendingInstallments = $installmentsQuery->get();

        // 4. Saídas Previstas (Contas a Pagar em aberto e não canceladas)
        $payablesQuery = Payable::query()
            ->where('space_id', $spaceModel->id)
            ->whereNotNull('amount_cents')
            ->whereRaw('paid_cents < amount_cents')
            ->whereNull('cancelled_at');

        if ($view === 'accrual') {
            $payablesQuery->whereBetween('created_at', [$startDate, $endDate]);
        } else {
            $payablesQuery->whereBetween('due_date', [$startDateStr, $endDateStr]);
        }

        if ($categoryId !== null) {
            $payablesQuery->where('category_id', $categoryId);
        }
        $pendingPayables = $payablesQuery->get();

        // 5. Agrupamento Diário e Projeção
        $daily = [];
        $runningBalanceCents = $initialBalanceCents;
        $totalRealizedInflow = 0;
        $totalRealizedOutflow = 0;
        $totalProjectedInflow = 0;
        $totalProjectedOutflow = 0;

        $currentDay = $startDate->copy();
        $todayStr = now($tz)->toDateString();

        for ($i = 0; $i < $days; $i++) {
            $dayStr = $currentDay->toDateString();

            // Realizados do dia
            $dayMovements = $movements->filter(fn ($m) => $m->effective_date->toDateString() === $dayStr);
            $realizedInflow = (int) $dayMovements->filter(fn ($m) => $m->amount_cents > 0)->sum('amount_cents');
            $realizedOutflow = (int) abs($dayMovements->filter(fn ($m) => $m->amount_cents < 0)->sum('amount_cents'));

            // Previstos do dia
            $dayInstallments = $pendingInstallments->filter(function ($inst) use ($dayStr, $view) {
                $targetDate = $view === 'accrual' ? $inst->created_at?->toDateString() : $inst->due_date?->toDateString();

                return $targetDate === $dayStr;
            });
            $projectedInflow = (int) $dayInstallments->sum(fn ($inst) => $inst->remainingCents());

            $dayPayables = $pendingPayables->filter(function ($p) use ($dayStr, $view) {
                $targetDate = $view === 'accrual' ? $p->created_at?->toDateString() : $p->due_date?->toDateString();

                return $targetDate === $dayStr;
            });
            $projectedOutflow = (int) $dayPayables->sum(fn ($p) => $p->remainingCents() ?? 0);

            // Se o dia já passou ou é hoje, o realizado compõe o caixa
            // Se o dia é futuro, o projetado compõe a projeção
            $isPastOrToday = $dayStr <= $todayStr;
            $netChange = $isPastOrToday
                ? ($realizedInflow - $realizedOutflow)
                : ($projectedInflow - $projectedOutflow);

            $runningBalanceCents += $netChange;

            $totalRealizedInflow += $realizedInflow;
            $totalRealizedOutflow += $realizedOutflow;
            $totalProjectedInflow += $projectedInflow;
            $totalProjectedOutflow += $projectedOutflow;

            $daily[] = [
                'date' => $dayStr,
                'realized_inflow_cents' => $realizedInflow,
                'realized_outflow_cents' => $realizedOutflow,
                'projected_inflow_cents' => $projectedInflow,
                'projected_outflow_cents' => $projectedOutflow,
                'projected_balance_cents' => $runningBalanceCents,
                'items_count' => $dayMovements->count() + $dayInstallments->count() + $dayPayables->count(),
            ];

            $currentDay->addDay();
        }

        $summary = [
            'realized_inflow_cents' => $totalRealizedInflow,
            'realized_outflow_cents' => $totalRealizedOutflow,
            'projected_inflow_cents' => $totalProjectedInflow,
            'projected_outflow_cents' => $totalProjectedOutflow,
            'final_projected_balance_cents' => $runningBalanceCents,
        ];

        // 6. Resposta em CSV caso export=true
        if ($request->boolean('export')) {
            $sanitizeRow = function (array $row): array {
                return array_map(function ($value) {
                    $str = (string) $value;
                    // Proteção contra Formula Injection (CSV Injection) em planilhas
                    if ($str !== '' && in_array($str[0], ['=', '+', '-', '@', "\t", "\r"], true)) {
                        return "'".$str;
                    }

                    return $str;
                }, $row);
            };

            return response()->stream(function () use ($daily, $initialBalanceCents, $summary, $sanitizeRow) {
                $handle = fopen('php://output', 'w');
                fputcsv($handle, $sanitizeRow(['Data', 'Entradas Realizadas', 'Saídas Realizadas', 'Entradas Previstas', 'Saídas Previstas', 'Saldo Projetado']));
                fputcsv($handle, $sanitizeRow(['Saldo Inicial', '-', '-', '-', '-', Money::fromCents($initialBalanceCents)]));
                foreach ($daily as $row) {
                    fputcsv($handle, $sanitizeRow([
                        $row['date'],
                        Money::fromCents($row['realized_inflow_cents']),
                        Money::fromCents($row['realized_outflow_cents']),
                        Money::fromCents($row['projected_inflow_cents']),
                        Money::fromCents($row['projected_outflow_cents']),
                        Money::fromCents($row['projected_balance_cents']),
                    ]));
                }
                fputcsv($handle, $sanitizeRow([
                    'Total / Final',
                    Money::fromCents($summary['realized_inflow_cents']),
                    Money::fromCents($summary['realized_outflow_cents']),
                    Money::fromCents($summary['projected_inflow_cents']),
                    Money::fromCents($summary['projected_outflow_cents']),
                    Money::fromCents($summary['final_projected_balance_cents']),
                ]));
                fclose($handle);
            }, 200, [
                'Content-Type' => 'text/csv; charset=UTF-8',
                'Content-Disposition' => 'attachment; filename="fluxo_caixa_'.now()->format('Ymd_His').'.csv"',
            ]);
        }

        return response()->json([
            'data' => [
                'initial_balance_cents' => $initialBalanceCents,
                'period_days' => $days,
                'view' => $view,
                'start_date' => $startDateStr,
                'end_date' => $endDateStr,
                'summary' => $summary,
                'daily' => $daily,
            ],
        ]);
    }

    private function calculateInitialBalance(int $spaceId, string $startDateStr, ?int $accountId): int
    {
        $accountsQuery = Account::query()->where('space_id', $spaceId);
        if ($accountId !== null) {
            $accountsQuery->where('id', $accountId);
        }
        $accounts = $accountsQuery->get();

        $openingTotal = 0;
        foreach ($accounts as $acc) {
            if ($acc->opening_balance_date->toDateString() < $startDateStr) {
                $openingTotal += $acc->opening_balance_cents;
            }
        }

        $priorMovementsQuery = AccountMovement::query()
            ->whereHas('account', fn ($q) => $q->where('space_id', $spaceId))
            ->where('effective_date', '<', $startDateStr);

        if ($accountId !== null) {
            $priorMovementsQuery->where('account_id', $accountId);
        }

        $priorMovementsTotal = (int) $priorMovementsQuery->sum('amount_cents');

        return $openingTotal + $priorMovementsTotal;
    }
}
