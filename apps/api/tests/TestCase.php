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
        // Proteção: a suíte só grava em banco PostgreSQL dedicado e homologado a testes.
        $connection = DB::connection();
        $config = $connection->getConfig();
        $driver = $connection->getDriverName();
        $host = (string) ($config['host'] ?? '');
        $port = (string) ($config['port'] ?? '');
        $database = (string) $connection->getDatabaseName();

        $validHostPort = ($port === '5440' && in_array($host, ['127.0.0.1', 'localhost'], true))
            || ($port === '5432' && $host === 'postgres');

        if ($driver !== 'pgsql' || ! $validHostPort || $database !== 'bigdevz_finance_test') {
            throw new RuntimeException("Suíte recusada: conexão [{$driver}://{$host}:{$port}/{$database}] não é o PostgreSQL homologado de testes (127.0.0.1:5440 ou container postgres:5432 / bigdevz_finance_test).");
        }

        // Validação no PDO de escrita direta para garantir o destino real das mutações
        $writePdo = $connection->getPdo();
        $currentDb = (string) $writePdo->query('SELECT current_database()')->fetchColumn();
        if ($currentDb !== 'bigdevz_finance_test') {
            throw new RuntimeException("Suíte recusada: PDO de escrita conectado a banco inesperado [{$currentDb}].");
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
