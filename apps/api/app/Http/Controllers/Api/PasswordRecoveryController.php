<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Closure;
use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

use function Illuminate\Support\defer;

class PasswordRecoveryController extends Controller
{
    public function requestLink(Request $request): JsonResponse
    {
        $data = $request->validate(['email' => ['required', 'string', 'email', 'max:255']]);

        $mailer = config('mail.default');
        if (config("mail.mailers.{$mailer}.transport") !== 'smtp') {
            return response()->json(['message' => 'A recuperação por e-mail está indisponível.'], 503);
        }

        defer(function () use ($data): void {
            $user = $this->findUser($data['email']);
            if ($user !== null) {
                Password::sendResetLink(['email' => $user->email]);
            }
        });

        return response()->json([
            'message' => 'Se o e-mail estiver cadastrado, você receberá um link para redefinir a senha.',
        ], 202);
    }

    public function reset(Request $request): Response
    {
        $data = $request->validate([
            'email' => ['required', 'string', 'email', 'max:255'],
            'token' => ['required', 'string', 'size:64'],
            'password' => ['bail', 'required', 'string', 'confirmed', function (
                string $attribute, string $value, Closure $fail,
            ): void {
                if (mb_strlen($value) < 8 || preg_match('/\p{L}/u', $value) !== 1) {
                    $fail('Use pelo menos 8 caracteres e inclua uma letra.');
                } elseif (strlen($value) > 72 || str_contains($value, "\0")) {
                    $fail('A senha deve ter até 72 bytes e não pode conter caracteres nulos.');
                }
            }],
        ]);

        $user = DB::transaction(function () use ($data): ?User {
            $user = User::query()
                ->whereRaw('LOWER(email) = ?', [mb_strtolower(trim($data['email']))])
                ->lockForUpdate()
                ->first();
            if ($user === null) {
                return null;
            }

            $data['email'] = $user->email;
            $status = Password::reset($data, function (User $account, string $password): void {
                $account->forceFill(['password' => $password])->setRememberToken(Str::random(60));
                $account->save();
                $account->tokens()->delete();
            });

            return $status === Password::PASSWORD_RESET ? $user : null;
        });

        if ($user === null) {
            throw ValidationException::withMessages(['token' => 'Link inválido ou expirado. Solicite um novo link.']);
        }

        event(new PasswordReset($user));

        return response()->noContent();
    }

    private function findUser(string $email): ?User
    {
        return User::query()->whereRaw('LOWER(email) = ?', [mb_strtolower(trim($email))])->first();
    }
}
