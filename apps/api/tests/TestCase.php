<?php

namespace Tests;

use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use RuntimeException;

abstract class TestCase extends BaseTestCase
{
    private static bool $migrated = false;

    /** Executa antes de DatabaseTransactions abrir a transação do teste. */
    protected function setUpTraits()
    {
        // Proteção: a suíte só grava em banco PostgreSQL dedicado a testes.
        $database = (string) DB::connection()->getDatabaseName();
        if (DB::connection()->getDriverName() !== 'pgsql' || ! str_ends_with($database, '_test')) {
            throw new RuntimeException("Suíte recusada: banco [{$database}] não é um PostgreSQL de testes.");
        }

        // Somente migrations pendentes; nunca recria nem esvazia o banco.
        if (! self::$migrated) {
            Artisan::call('migrate');
            self::$migrated = true;
        }

        return parent::setUpTraits();
    }

    /** @return array{0: User, 1: Space, 2: Space} */
    protected function userWithSpaces(): array
    {
        $user = User::factory()->create();

        return [$user, $user->spaces()->where('kind', 'PF')->firstOrFail(), $user->spaces()->where('kind', 'PJ')->firstOrFail()];
    }
}
