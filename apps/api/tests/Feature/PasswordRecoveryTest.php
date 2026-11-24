<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;
use Tests\TestCase;

class PasswordRecoveryTest extends TestCase
{
    use DatabaseTransactions;

    public function test_ac_auth_001_requests_are_generic_and_reset_tokens_are_single_use(): void
    {
        config(['mail.default' => 'smtp', 'app.url' => 'https://finance.example.test']);
        Notification::fake();
        [$user] = $this->userWithSpaces();
        $user->createToken('sessão anterior');

        $unknown = $this->postJson('/api/auth/forgot-password', ['email' => 'unknown@example.test']);
        $known = $this->postJson('/api/auth/forgot-password', ['email' => strtoupper($user->email)]);
        $known->assertAccepted()->assertExactJson($unknown->assertAccepted()->json());
        $notification = Notification::sent($user, ResetPassword::class)->sole();
        $this->assertStringStartsWith('https://finance.example.test/#redefinir-senha?', $notification->toMail($user)->actionUrl);

        $data = [
            'email' => $user->email,
            'token' => $notification->token,
            'password' => 'á2345678',
            'password_confirmation' => 'á2345678',
        ];
        foreach (['á234567', '12345678'] as $invalidPassword) {
            $this->postJson('/api/auth/reset-password', array_replace($data, [
                'password' => $invalidPassword,
                'password_confirmation' => $invalidPassword,
            ]))->assertUnprocessable()->assertJsonValidationErrors('password');
        }

        $this->postJson('/api/auth/reset-password', $data)->assertNoContent();
        $this->assertTrue(Hash::check($data['password'], $user->refresh()->password));
        $this->assertSame(0, $user->tokens()->count());
        $this->postJson('/api/auth/reset-password', $data)->assertUnprocessable();
    }

    public function test_ac_auth_002_email_has_branded_html_and_plain_text(): void
    {
        config(['app.url' => 'https://finance.example.test']);
        $user = new User(['email' => 'preview@example.test']);
        $mail = (new ResetPassword(str_repeat('a', 64)))->toMail($user);

        $this->assertSame('Redefinição de senha — BigDev.Z Finance', $mail->subject);
        $html = (string) $mail->render();
        $this->assertStringContainsString('lang="pt-BR"', $html);
        $this->assertStringContainsString('BigDev.Z Finance', $html);
        $this->assertStringContainsString('href="'.e($mail->actionUrl).'"', $html);
        $this->assertStringContainsString('60 minutos', $html);

        $plain = view($mail->view['text'], $mail->data())->render();
        $this->assertStringContainsString($mail->actionUrl, $plain);
        $this->assertStringContainsString('60 minutos', $plain);
    }

    public function test_ac_auth_001_rejects_expired_tokens_and_disables_non_smtp_delivery(): void
    {
        config(['mail.default' => 'log']);
        Notification::fake();
        [$user] = $this->userWithSpaces();

        $this->postJson('/api/auth/forgot-password', ['email' => $user->email])->assertServiceUnavailable();
        Notification::assertNothingSent();

        $token = Password::createToken($user);
        $this->travel(61)->minutes();
        $this->postJson('/api/auth/reset-password', [
            'email' => $user->email,
            'token' => $token,
            'password' => 'uma senha longa fictícia',
            'password_confirmation' => 'uma senha longa fictícia',
        ])->assertUnprocessable()->assertJsonValidationErrors('token');
    }
}
