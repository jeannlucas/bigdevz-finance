<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;
use RuntimeException;

/**
 * Dados exclusivamente fictícios para desenvolvimento local. A senha é
 * pública por design e, por isso, o seeder se recusa a rodar em produção.
 */
class DatabaseSeeder extends Seeder
{
    public const EMAIL = 'demo@example.com';

    public const PASSWORD = 'demo-bigdevz-local';

    public function run(): void
    {
        if (app()->isProduction()) {
            throw new RuntimeException('Seed demonstrativo bloqueado em produção.');
        }

        $user = User::query()->firstOrCreate(
            ['email' => self::EMAIL],
            ['name' => 'Pessoa Demonstração', 'password' => self::PASSWORD, 'email_verified_at' => now()],
        );

        $pf = $user->spaces()->where('kind', 'PF')->firstOrFail();
        $pj = $user->spaces()->where('kind', 'PJ')->firstOrFail();
        $pf->accounts()->firstOrCreate(['name' => 'Banco Fictício PF'], [
            'opening_balance_cents' => 100000, 'opening_balance_date' => '2026-01-01',
        ]);
        $pj->accounts()->firstOrCreate(['name' => 'Banco Fictício PJ'], [
            'opening_balance_cents' => 500000, 'opening_balance_date' => '2026-01-01',
        ]);
    }
}
