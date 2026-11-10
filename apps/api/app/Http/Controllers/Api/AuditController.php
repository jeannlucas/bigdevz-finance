<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ObligationChange;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AuditController extends Controller
{
    public function index(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);

        $query = ObligationChange::query()
            ->where('space_id', $spaceModel->id)
            ->with('user:id,name,email')
            ->orderByDesc('id');

        if ($request->filled('subject')) {
            $query->where('subject', $request->query('subject'));
        }

        if ($request->filled('subject_id')) {
            $query->where('subject_id', $request->integer('subject_id'));
        }

        $limit = min(max($request->integer('limit', 50), 1), 200);
        $changes = $query->limit($limit)->get();

        if ($request->boolean('critical_only')) {
            $changes = $changes->filter(fn (ObligationChange $c) => $c->isCritical())->values();
        }

        $data = $changes->map(fn (ObligationChange $change) => [
            'id' => $change->id,
            'subject' => $change->subject,
            'subject_id' => $change->subject_id,
            'action' => $change->action,
            'is_critical' => $change->isCritical(),
            'user' => $change->user ? [
                'id' => $change->user->id,
                'name' => $change->user->name,
                'email' => $change->user->email,
            ] : null,
            'before' => $change->before,
            'after' => $change->after,
            'diff' => $this->calculateDiff($change->before ?? [], $change->after ?? []),
            'reason' => $change->reason,
            'created_at' => $change->created_at?->toIso8601String(),
        ]);

        return response()->json([
            'data' => $data,
        ]);
    }

    private function calculateDiff(array $before, array $after): array
    {
        $diff = [];
        $allKeys = array_unique(array_merge(array_keys($before), array_keys($after)));

        foreach ($allKeys as $key) {
            $valBefore = $before[$key] ?? null;
            $valAfter = $after[$key] ?? null;

            if ($valBefore !== $valAfter) {
                $diff[$key] = [
                    'before' => $valBefore,
                    'after' => $valAfter,
                ];
            }
        }

        return $diff;
    }
}
