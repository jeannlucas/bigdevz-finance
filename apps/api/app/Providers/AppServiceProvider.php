<?php

namespace App\Providers;

use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        ResetPassword::toMailUsing(function (object $user, string $token): MailMessage {
            $query = http_build_query(['email' => $user->getEmailForPasswordReset(), 'token' => $token]);
            $url = rtrim(config('app.url'), '/').'/#redefinir-senha?'.$query;

            return (new MailMessage)
                ->subject('Redefinição de senha — BigDev.Z Finance')
                ->action('Redefinir senha', $url)
                ->view([
                    'html' => 'mail.password-recovery',
                    'text' => 'mail.password-recovery-text',
                ], [
                    'expiresInMinutes' => config('auth.passwords.'.config('auth.defaults.passwords').'.expire'),
                ]);
        });

        RateLimiter::for('login', fn (Request $request) => Limit::perMinute(5)
            ->by(mb_strtolower((string) $request->input('email')).'|'.$request->ip()));
    }
}
