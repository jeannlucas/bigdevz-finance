<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Space;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class SpaceMemberController extends Controller
{
    public function index(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);

        $members = $spaceModel->members()
            ->orderBy('name')
            ->get()
            ->map(fn (User $user) => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'role' => (string) $user->pivot->role,
                'is_owner' => $spaceModel->user_id === $user->id,
            ]);

        return response()->json([
            'data' => $members,
        ]);
    }

    public function store(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $spaceModel->ensureCan($request->user(), 'manage_members');

        $data = $request->validate([
            'email' => ['required', 'email'],
            'role' => ['required', 'string', Rule::in(Space::ROLES)],
        ]);

        $user = User::query()->where('email', $data['email'])->firstOrFail();

        $spaceModel->members()->syncWithoutDetaching([
            $user->id => ['role' => $data['role']],
        ]);

        return response()->json([
            'message' => 'Membro adicionado ou atualizado com sucesso.',
            'data' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'role' => $data['role'],
                'is_owner' => $spaceModel->user_id === $user->id,
            ],
        ], 200);
    }

    public function destroy(Request $request, string $space, string $member): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $spaceModel->ensureCan($request->user(), 'manage_members');

        $targetUser = $spaceModel->members()->findOrFail($member);

        if ($spaceModel->user_id === $targetUser->id) {
            abort(422, 'Não é permitido remover o proprietário do espaço.');
        }

        $spaceModel->members()->detach($targetUser->id);

        return response()->json([
            'message' => 'Membro removido do espaço com sucesso.',
        ]);
    }
}
