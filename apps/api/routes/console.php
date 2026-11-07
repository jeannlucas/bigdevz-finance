<?php

use App\Actions\Payables\GenerateObligations;
use App\Models\User;
use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schedule;
use Illuminate\Support\Str;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// A pagar: ocorrências de recorrências e faturas de cartões até o horizonte
// (mês atual + 12). Idempotente; o serviço `scheduler` do Compose executa
// `schedule:work`. Log só com contagens, sem dados financeiros.
Artisan::command('payables:generate', function (GenerateObligations $generate) {
    $created = $generate->all();
    Log::info('payables:generate', $created + ['horizon' => GenerateObligations::horizon()]);
    $this->info("payables:generate: {$created['occurrences']} ocorrências e {$created['bills']} faturas criadas até ".GenerateObligations::horizon().'.');
})->purpose('Gera ocorrências recorrentes e faturas de cartão até o horizonte');

// Saída (só contagens e horizonte) em storage/logs/payables-generate.log.
Schedule::command('payables:generate')->hourly()->withoutOverlapping()
    ->appendOutputTo(storage_path('logs/payables-generate.log'));

Artisan::command('user:create {email} {--name=Usuário} {--password=}', function () {
    $email = $this->argument('email');
    $name = $this->option('name');
    $password = $this->option('password') ?: Str::random(16);

    $user = User::query()->firstOrCreate(
        ['email' => $email],
        ['name' => $name, 'password' => $password, 'email_verified_at' => now()]
    );

    $this->info("Usuário {$user->email} pronto (ID: {$user->id}).");
    if ($this->option('password')) {
        $this->info('Senha definida.');
    } else {
        $this->warn("Senha gerada: {$password}");
    }
})->purpose('Cria um usuário com seus espaços PF/PJ');
