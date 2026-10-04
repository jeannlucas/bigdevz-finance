<?php

namespace Tests\Feature;

use App\Actions\Receivables\CreateAgreement;
use App\Models\Account;
use App\Models\Installment;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use PDO;
use RuntimeException;
use Tests\TestCase;

/**
 * Cenário 11 com processos e conexões reais. Os dados precisam estar
 * gravados para os workers enxergarem; o tearDown remove apenas o que este
 * teste criou no banco de testes.
 */
class ConcurrentReceiptsTest extends TestCase
{
    private User $user;

    private Space $space;

    private Account $account;

    private Installment $installment;

    protected function setUp(): void
    {
        parent::setUp();
        $this->user = User::factory()->create();
        $this->space = $this->user->spaces()->where('kind', 'PF')->firstOrFail();
        $this->account = $this->space->accounts()->create([
            'name' => 'Conta', 'opening_balance_cents' => 100000, 'opening_balance_date' => '2026-01-01',
        ]);
        $agreement = app(CreateAgreement::class)->handle($this->space, 'Venda de veículo', '24000.00', 12, '2026-02-10');
        $this->installment = $agreement->installments()->firstOrFail();
    }

    protected function tearDown(): void
    {
        $receipts = Receipt::query()->where('space_id', $this->space->id)->pluck('id');
        DB::table('account_movements')->whereIn('receipt_id', $receipts)->delete();
        DB::table('receipts')->whereIn('id', $receipts)->delete();
        DB::table('installments')->where('space_id', $this->space->id)->delete();
        DB::table('agreements')->where('space_id', $this->space->id)->delete();
        DB::table('accounts')->where('space_id', $this->space->id)->delete();
        DB::table('spaces')->where('user_id', $this->user->id)->delete();
        DB::table('users')->where('id', $this->user->id)->delete();
        parent::tearDown();
    }

    public function test_two_simultaneous_receipts_cannot_exceed_remaining(): void
    {
        $results = $this->race([[150000, 'corrida-a'], [150000, 'corrida-b']]);

        $this->assertEqualsCanonicalizing(['created', 'rejected'], array_column($results, 'result'));
        $this->assertSame(150000, $this->installment->fresh()->received_cents);
        $this->assertSame(1, Receipt::query()->where('space_id', $this->space->id)->count());
        $this->assertSame(250000, $this->account->fresh()->balanceCents());
    }

    public function test_simultaneous_receipts_that_fit_are_both_recorded(): void
    {
        $results = $this->race([[100000, 'cabe-a'], [100000, 'cabe-b']]);

        $this->assertSame(['created', 'created'], array_column($results, 'result'));
        $this->assertSame(200000, $this->installment->fresh()->received_cents);
        $this->assertSame(300000, $this->account->fresh()->balanceCents());
    }

    public function test_simultaneous_resend_with_same_key_records_once(): void
    {
        $results = $this->race([[200000, 'reenvio'], [200000, 'reenvio']]);

        $this->assertEqualsCanonicalizing(['created', 'replayed'], array_column($results, 'result'));
        $this->assertSame(1, Receipt::query()->where('space_id', $this->space->id)->count());
        $this->assertSame(300000, $this->account->fresh()->balanceCents());
    }

    public function test_simultaneous_same_key_with_different_amount_conflicts(): void
    {
        $results = $this->race([[50000, 'mesma'], [60000, 'mesma']]);

        $this->assertEqualsCanonicalizing(['created', 'conflict'], array_column($results, 'result'));
        $this->assertSame(1, Receipt::query()->where('space_id', $this->space->id)->count());
    }

    /**
     * Segura o lock da parcela, inicia os workers, espera os dois ficarem
     * bloqueados no PostgreSQL e só então libera, forçando a disputa.
     *
     * @param  list<array{0: int, 1: string}>  $requests
     * @return list<array<string, mixed>>
     */
    private function race(array $requests): array
    {
        $config = config('database.connections.pgsql');
        $holder = new PDO("pgsql:host={$config['host']};port={$config['port']};dbname={$config['database']}", $config['username'], $config['password']);
        $holder->beginTransaction();
        $holder->prepare('SELECT id FROM installments WHERE id = ? FOR UPDATE')->execute([$this->installment->id]);

        $env = array_merge(getenv(), [
            'APP_ENV' => 'testing', 'APP_KEY' => config('app.key'), 'DB_CONNECTION' => 'pgsql',
            'DB_HOST' => $config['host'], 'DB_PORT' => (string) $config['port'], 'DB_DATABASE' => $config['database'],
            'DB_USERNAME' => $config['username'], 'DB_PASSWORD' => $config['password'],
        ]);
        $workers = [];
        foreach ($requests as [$cents, $key]) {
            $process = proc_open([PHP_BINARY, base_path('tests/Support/receive_worker.php'),
                (string) $this->user->id, (string) $this->space->id, (string) $this->installment->id,
                (string) $this->account->id, (string) $cents, '2026-02-10', $key,
            ], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, base_path(), $env);
            $workers[] = [$process, $pipes];
        }

        $deadline = microtime(true) + 15;
        do {
            usleep(50_000);
            // Dentro da transação o pg_stat_activity fica congelado; renovar a cada leitura.
            $holder->query('SELECT pg_stat_clear_snapshot()');
            $waiting = (int) $holder->query("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'")->fetchColumn();
        } while ($waiting < count($requests) && microtime(true) < $deadline);
        $holder->commit();

        $results = array_map(static function (array $worker): array {
            [$process, $pipes] = $worker;
            $out = stream_get_contents($pipes[1]);
            $err = stream_get_contents($pipes[2]);
            $code = proc_close($process);
            $decoded = json_decode((string) $out, true);
            if ($code !== 0 || ! is_array($decoded)) {
                throw new RuntimeException("Worker falhou ({$code}): {$out} {$err}");
            }

            return $decoded;
        }, $workers);
        $this->assertSame(count($requests), $waiting, 'Os workers não chegaram a disputar o lock: '.json_encode($results));

        return $results;
    }
}
