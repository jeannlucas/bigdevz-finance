<?php

namespace Tests\Concerns;

use PDO;
use RuntimeException;

/**
 * Disputa real entre processos PHP com conexões PostgreSQL próprias: uma
 * conexão segura as linhas indicadas (FOR UPDATE), os workers são iniciados,
 * espera-se todos ficarem bloqueados no PostgreSQL e só então se libera. Os
 * dados precisam estar gravados (sem DatabaseTransactions) para os workers
 * enxergarem.
 */
trait RacesProcesses
{
    /**
     * @param  list<list<string>>  $commands  [script relativo à API, ...argumentos]; "artisan" roda um comando.
     * @param  list<array{0: string, 1: int|string}>  $locks  [tabela, id] ou ['advisory', chave] seguros até todos esperarem.
     * @return list<array<string, mixed>> JSON de cada worker (ou ['output' => ...] para artisan)
     */
    private function raceProcesses(array $commands, array $locks): array
    {
        $config = config('database.connections.pgsql');
        $holder = new PDO("pgsql:host={$config['host']};port={$config['port']};dbname={$config['database']}", $config['username'], $config['password']);
        $holder->beginTransaction();
        foreach ($locks as [$table, $id]) {
            // "advisory": o lock consultivo de uma chave idempotente ("idempotency:{espaço}:{chave}").
            $table === 'advisory'
                ? $holder->prepare('SELECT pg_advisory_xact_lock(hashtextextended(?, 0))')->execute([$id])
                : $holder->prepare("SELECT id FROM {$table} WHERE id = ? FOR UPDATE")->execute([$id]);
        }

        $env = array_merge(getenv(), [
            'APP_ENV' => 'testing', 'APP_KEY' => config('app.key'), 'DB_CONNECTION' => 'pgsql',
            'DB_HOST' => $config['host'], 'DB_PORT' => (string) $config['port'], 'DB_DATABASE' => $config['database'],
            'DB_USERNAME' => $config['username'], 'DB_PASSWORD' => $config['password'],
        ]);
        $workers = [];
        foreach ($commands as $command) {
            $process = proc_open([PHP_BINARY, base_path($command[0]), ...array_slice($command, 1)],
                [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, base_path(), $env);
            $workers[] = [$process, $pipes, $command[0] === 'artisan'];
        }

        $deadline = microtime(true) + 15;
        do {
            usleep(50_000);
            // Dentro da transação o pg_stat_activity fica congelado; renovar a cada leitura.
            $holder->query('SELECT pg_stat_clear_snapshot()');
            $waiting = (int) $holder->query("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'")->fetchColumn();
        } while ($waiting < count($commands) && microtime(true) < $deadline);
        $holder->commit();

        $results = array_map(static function (array $worker): array {
            [$process, $pipes, $raw] = $worker;
            $out = stream_get_contents($pipes[1]);
            $err = stream_get_contents($pipes[2]);
            $code = proc_close($process);
            $decoded = $raw ? ['output' => trim((string) $out)] : json_decode((string) $out, true);
            if ($code !== 0 || ! is_array($decoded)) {
                throw new RuntimeException("Worker falhou ({$code}): {$out} {$err}");
            }

            return $decoded;
        }, $workers);
        $this->assertSame(count($commands), $waiting, 'Os workers não chegaram a disputar o lock: '.json_encode($results));

        return $results;
    }
}
