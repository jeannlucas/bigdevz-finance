<?php

namespace App\Http\Controllers\Api;

use App\Actions\Payables\GenerateObligations;
use App\Domain\Receivables\Money;
use App\Http\Controllers\Controller;
use App\Models\AlertState;
use App\Models\Space;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AlertController extends Controller
{
    /** Lista os alertas ativos para o usuário no espaço, com suporte a filtro de dispensados. */
    public function index(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $user = $request->user();

        $alerts = $this->gatherAlerts($spaceModel, $user);
        $includeDismissed = filter_var($request->query('include_dismissed', false), FILTER_VALIDATE_BOOLEAN);

        $filtered = array_values(array_filter($alerts, function ($alert) use ($includeDismissed) {
            return $includeDismissed || ! $alert['is_dismissed'];
        }));

        $unreadActiveCount = count(array_filter($alerts, fn ($a) => ! $a['is_dismissed'] && ! $a['is_read']));

        return response()->json([
            'data' => $filtered,
            'meta' => [
                'unread_active_count' => $unreadActiveCount,
                'total_active_count' => count(array_filter($alerts, fn ($a) => ! $a['is_dismissed'])),
            ],
        ]);
    }

    /** Retorna apenas a contagem para o badge da barra superior. */
    public function badge(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $user = $request->user();

        $alerts = $this->gatherAlerts($spaceModel, $user);
        $unreadActiveCount = count(array_filter($alerts, fn ($a) => ! $a['is_dismissed'] && ! $a['is_read']));

        return response()->json([
            'data' => [
                'unread_active_count' => $unreadActiveCount,
            ],
        ]);
    }

    /** Marca um alerta como lido. */
    public function read(Request $request, string $space, string $alertKey): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $user = $request->user();

        $state = AlertState::updateOrCreate([
            'user_id' => $user->id,
            'space_id' => $spaceModel->id,
            'alert_key' => $alertKey,
        ], [
            'read_at' => now(),
        ]);

        return response()->json([
            'data' => [
                'alert_key' => $state->alert_key,
                'is_read' => $state->isRead(),
                'is_dismissed' => $state->isDismissed(),
                'read_at' => $state->read_at?->toIso8601String(),
            ],
        ]);
    }

    /** Marca um alerta como dispensado (removido da lista ativa). */
    public function dismiss(Request $request, string $space, string $alertKey): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $user = $request->user();

        $state = AlertState::updateOrCreate([
            'user_id' => $user->id,
            'space_id' => $spaceModel->id,
            'alert_key' => $alertKey,
        ], [
            'dismissed_at' => now(),
        ]);

        return response()->json([
            'data' => [
                'alert_key' => $state->alert_key,
                'is_read' => $state->isRead(),
                'is_dismissed' => $state->isDismissed(),
                'dismissed_at' => $state->dismissed_at?->toIso8601String(),
            ],
        ]);
    }

    /** @return list<array<string, mixed>> */
    private function gatherAlerts(Space $space, $user): array
    {
        $today = GenerateObligations::today();
        $states = AlertState::where('user_id', $user->id)
            ->where('space_id', $space->id)
            ->get()
            ->keyBy('alert_key');

        $alerts = [];

        // 1. Contas a pagar vencidas
        $overduePayables = $space->payables()
            ->whereNull('cancelled_at')
            ->whereNotNull('amount_cents')
            ->whereColumn('paid_cents', '<', 'amount_cents')
            ->where('due_date', '<', $today)
            ->orderBy('due_date')
            ->get();

        foreach ($overduePayables as $payable) {
            $key = "payable:{$payable->id}";
            $state = $states->get($key);
            $remaining = $payable->remainingCents() ?? 0;

            $alerts[] = [
                'key' => $key,
                'target_id' => $payable->id,
                'type' => 'payable_overdue',
                'title' => 'Conta a pagar vencida: '.$payable->description,
                'description' => "Venceu em {$payable->due_date->format('d/m/Y')}. Restante: ".Money::fromCents($remaining),
                'due_date' => $payable->due_date->toDateString(),
                'amount' => Money::fromCents($remaining),
                'amount_cents' => $remaining,
                'is_critical' => true,
                'is_read' => $state?->isRead() ?? false,
                'is_dismissed' => $state?->isDismissed() ?? false,
                'read_at' => $state?->read_at?->toIso8601String(),
                'dismissed_at' => $state?->dismissed_at?->toIso8601String(),
            ];
        }

        // 2. Contas a receber (parcelas) vencidas
        $overdueInstallments = $space->installments()
            ->with('agreement')
            ->whereColumn('received_cents', '<', 'amount_cents')
            ->where('due_date', '<', $today)
            ->orderBy('due_date')
            ->get();

        foreach ($overdueInstallments as $installment) {
            $key = "installment:{$installment->id}";
            $state = $states->get($key);
            $remaining = $installment->remainingCents() ?? 0;

            $alerts[] = [
                'key' => $key,
                'target_id' => $installment->id,
                'type' => 'installment_overdue',
                'title' => 'Conta a receber vencida: '.($installment->agreement?->description ?? 'Parcela'),
                'description' => "Venceu em {$installment->due_date->format('d/m/Y')}. Restante: ".Money::fromCents($remaining),
                'due_date' => $installment->due_date->toDateString(),
                'amount' => Money::fromCents($remaining),
                'amount_cents' => $remaining,
                'is_critical' => true,
                'is_read' => $state?->isRead() ?? false,
                'is_dismissed' => $state?->isDismissed() ?? false,
                'read_at' => $state?->read_at?->toIso8601String(),
                'dismissed_at' => $state?->dismissed_at?->toIso8601String(),
            ];
        }

        // 3. Faturas de cartão e recorrências variáveis aguardando valor
        $awaitingPayables = $space->payables()
            ->whereNull('cancelled_at')
            ->whereNull('amount_cents')
            ->orderBy('due_date')
            ->get();

        foreach ($awaitingPayables as $payable) {
            $key = "payable:{$payable->id}";
            $state = $states->get($key);

            $alerts[] = [
                'key' => $key,
                'target_id' => $payable->id,
                'type' => 'awaiting_amount',
                'title' => 'Aguardando valor: '.$payable->description,
                'description' => "Vencimento previsto para {$payable->due_date->format('d/m/Y')}.",
                'due_date' => $payable->due_date->toDateString(),
                'amount' => $payable->estimated_amount_cents ? Money::fromCents($payable->estimated_amount_cents) : null,
                'amount_cents' => $payable->estimated_amount_cents,
                'is_critical' => false,
                'is_read' => $state?->isRead() ?? false,
                'is_dismissed' => $state?->isDismissed() ?? false,
                'read_at' => $state?->read_at?->toIso8601String(),
                'dismissed_at' => $state?->dismissed_at?->toIso8601String(),
            ];
        }

        return $alerts;
    }
}
