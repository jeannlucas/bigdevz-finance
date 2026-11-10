<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ObligationChange;
use App\Models\SpaceClosingLog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AccountingPeriodController extends Controller
{
    public function show(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);

        $history = SpaceClosingLog::query()
            ->where('space_id', $spaceModel->id)
            ->with('user:id,name,email')
            ->orderByDesc('id')
            ->limit(20)
            ->get();

        return response()->json([
            'data' => [
                'closed_until' => $spaceModel->closed_until?->format('Y-m-d'),
                'is_closed' => $spaceModel->closed_until !== null,
                'history' => $history,
            ],
        ]);
    }

    public function close(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $spaceModel->ensureCan($request->user(), 'close_period');

        $data = $request->validate([
            'closed_until' => ['required', 'date_format:Y-m-d'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        $previous = $spaceModel->closed_until?->format('Y-m-d');
        $newClosedUntil = $data['closed_until'];

        $spaceModel->update(['closed_until' => $newClosedUntil]);

        SpaceClosingLog::create([
            'space_id' => $spaceModel->id,
            'user_id' => $request->user()->id,
            'action' => SpaceClosingLog::ACTION_CLOSED,
            'closed_until' => $newClosedUntil,
            'previous_closed_until' => $previous,
            'reason' => $data['reason'] ?? 'Fechamento de período contábil',
        ]);

        ObligationChange::create([
            'space_id' => $spaceModel->id,
            'user_id' => $request->user()->id,
            'subject' => 'period_closing',
            'subject_id' => $spaceModel->id,
            'action' => 'close',
            'before' => ['closed_until' => $previous],
            'after' => ['closed_until' => $newClosedUntil],
            'reason' => $data['reason'] ?? 'Fechamento de período contábil',
        ]);

        return response()->json([
            'message' => 'Período contábil fechado com sucesso.',
            'closed_until' => $newClosedUntil,
        ]);
    }

    public function reopen(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $spaceModel->ensureCan($request->user(), 'reopen_period');

        $data = $request->validate([
            'reason' => ['required', 'string', 'min:5', 'max:500'],
            'closed_until' => ['nullable', 'date_format:Y-m-d'],
        ], [
            'reason.required' => 'A justificativa de reabertura é obrigatória.',
            'reason.min' => 'A justificativa deve ter no mínimo 5 caracteres.',
        ]);

        $previous = $spaceModel->closed_until?->format('Y-m-d');
        $newClosedUntil = $data['closed_until'] ?? null;

        $spaceModel->update(['closed_until' => $newClosedUntil]);

        SpaceClosingLog::create([
            'space_id' => $spaceModel->id,
            'user_id' => $request->user()->id,
            'action' => SpaceClosingLog::ACTION_REOPENED,
            'closed_until' => $newClosedUntil,
            'previous_closed_until' => $previous,
            'reason' => $data['reason'],
        ]);

        ObligationChange::create([
            'space_id' => $spaceModel->id,
            'user_id' => $request->user()->id,
            'subject' => 'period_closing',
            'subject_id' => $spaceModel->id,
            'action' => 'reopen',
            'before' => ['closed_until' => $previous],
            'after' => ['closed_until' => $newClosedUntil],
            'reason' => $data['reason'],
        ]);

        return response()->json([
            'message' => 'Período contábil reaberto com sucesso.',
            'closed_until' => $newClosedUntil,
        ]);
    }
}
