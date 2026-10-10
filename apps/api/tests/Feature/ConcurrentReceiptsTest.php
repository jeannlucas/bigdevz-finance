<?php

namespace Tests\Feature;

use App\Actions\Receivables\CreateAgreement;
use App\Actions\Receivables\ReceiveInstallment;
use App\Models\Account;
use App\Models\Installment;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\RacesProcesses;
use Tests\TestCase;

/**
 * Cenário 11 com processos e conexões reais. Os dados precisam estar
 * gravados para os workers enxergarem; o tearDown remove apenas o que este
 * teste criou no banco de testes.
 */
class ConcurrentReceiptsTest extends TestCase
{
    use RacesProcesses;

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
        DB::table('idempotency_keys')->where('space_id', $this->space->id)->delete();
        DB::table('account_opening_adjustments')->where('space_id', $this->space->id)->delete();
        DB::table('account_movements')->where('account_id', $this->account->id)->delete();
        DB::table('receipt_reversals')->where('space_id', $this->space->id)->delete();
        DB::table('receipts')->where('space_id', $this->space->id)->delete();
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

    public function test_two_reversals_of_the_same_receipt_compensate_once(): void
    {
        $receipt = $this->recordReceipt(50000, 'base');
        $results = $this->raceWorkers([$this->reverseWorker($receipt, 'estorno-a'), $this->reverseWorker($receipt, 'estorno-b')]);

        $this->assertEqualsCanonicalizing(['created', 'rejected'], array_column($results, 'result'));
        $this->assertSame(1, DB::table('receipt_reversals')->where('receipt_id', $receipt)->count());
        $this->assertSame(0, $this->installment->fresh()->received_cents);
        $this->assertSame(100000, $this->account->fresh()->balanceCents());
    }

    public function test_simultaneous_reversal_with_same_key_compensates_once(): void
    {
        $receipt = $this->recordReceipt(50000, 'base');
        $results = $this->raceWorkers([$this->reverseWorker($receipt, 'mesmo'), $this->reverseWorker($receipt, 'mesmo')]);

        $this->assertEqualsCanonicalizing(['created', 'replayed'], array_column($results, 'result'));
        $this->assertSame(1, DB::table('account_movements')->where('amount_cents', '<', 0)->where('account_id', $this->account->id)->count());
        $this->assertSame(100000, $this->account->fresh()->balanceCents());
    }

    public function test_correction_and_new_receipt_cannot_exceed_installment(): void
    {
        // Restante 150000; corrigir 50000 para 200000 cabe sozinho, o novo de 150000 também; juntos não.
        $receipt = $this->recordReceipt(50000, 'base');
        $results = $this->raceWorkers([
            $this->reverseWorker($receipt, 'corrige', [(string) $this->account->id, '200000', '2026-02-10']),
            ['tests/Support/receive_worker.php', (string) $this->user->id, (string) $this->space->id,
                (string) $this->installment->id, (string) $this->account->id, '150000', '2026-02-10', 'novo'],
        ]);

        $this->assertEqualsCanonicalizing(['created', 'rejected'], array_column($results, 'result'));
        $received = $this->installment->fresh()->received_cents;
        $this->assertSame(200000, $received);
        $this->assertSame(100000 + $received, $this->account->fresh()->balanceCents());
    }

    public function test_two_corrections_of_the_same_receipt_apply_once(): void
    {
        $receipt = $this->recordReceipt(50000, 'base');
        $results = $this->raceWorkers([
            $this->reverseWorker($receipt, 'cor-a', [(string) $this->account->id, '40000', '2026-02-10']),
            $this->reverseWorker($receipt, 'cor-b', [(string) $this->account->id, '60000', '2026-02-10']),
        ]);

        $this->assertEqualsCanonicalizing(['created', 'rejected'], array_column($results, 'result'));
        $this->assertSame(2, Receipt::query()->where('space_id', $this->space->id)->count());
        $received = $this->installment->fresh()->received_cents;
        $this->assertContains($received, [40000, 60000]);
        $this->assertSame(100000 + $received, $this->account->fresh()->balanceCents());
    }

    public function test_opening_date_and_receipt_never_leave_a_movement_before_opening(): void
    {
        $results = $this->raceWorkers([
            $this->accountWorker('adjust', '100000', '2026-02-12', 'abre-depois'),
            $this->receiveWorker(50000, '2026-02-10', 'recebe-antes'),
        ]);

        $this->assertEqualsCanonicalizing(['created', 'rejected'], array_column($results, 'result'));
        $account = $this->account->fresh();
        $first = DB::table('account_movements')->where('account_id', $account->id)->min('effective_date');
        $this->assertTrue($first === null || $first >= $account->opening_balance_date->toDateString(), 'nenhuma movimentação antes da abertura');
    }

    public function test_opening_balance_and_reversal_keep_exact_balance(): void
    {
        $receipt = $this->recordReceipt(50000, 'base');
        $results = $this->raceWorkers([
            $this->accountWorker('adjust', '200000', '2026-01-01', 'abre-maior'),
            $this->reverseWorker($receipt, 'estorna'),
        ]);

        $this->assertSame(['created', 'created'], array_column($results, 'result'));
        $this->assertSame(200000, $this->account->fresh()->balanceCents());
        $this->assertSame(1, DB::table('account_opening_adjustments')->where('account_id', $this->account->id)->count());
    }

    public function test_archive_and_new_receipt_are_serialized(): void
    {
        $results = $this->raceWorkers([
            $this->accountWorker('archive'),
            $this->receiveWorker(50000, '2026-02-10', 'recebe'),
        ]);

        $receipt = collect($results)->firstWhere('receipt');
        $account = $this->account->fresh();
        $this->assertNotNull($account->archived_at);
        if ($receipt === null) {
            // Arquivou antes: recusado pela regra de conta ativa, sem dinheiro novo.
            $this->assertSame(0, Receipt::query()->where('space_id', $this->space->id)->count());
            $this->assertSame(100000, $account->balanceCents());
        } else {
            // Recebeu antes: o recebimento terminou antes do arquivamento.
            $this->assertLessThanOrEqual($account->archived_at, Receipt::query()->findOrFail($receipt['receipt'])->created_at);
            $this->assertSame(150000, $account->balanceCents());
        }
    }

    /** Original ainda gravando quando a verificação chega: um só efeito. */
    public function test_simultaneous_partial_resend_with_same_key_records_once(): void
    {
        $results = $this->race([[50000, 'verificacao'], [50000, 'verificacao']]);

        $this->assertEqualsCanonicalizing(['created', 'replayed'], array_column($results, 'result'));
        $this->assertSame(1, Receipt::query()->where('space_id', $this->space->id)->count());
        $this->assertSame(1, DB::table('account_movements')->where('account_id', $this->account->id)->count());
        $this->assertSame(50000, $this->installment->fresh()->received_cents);
        $this->assertSame(150000, $this->account->fresh()->balanceCents());
    }

    public function test_simultaneous_same_key_with_different_amount_conflicts(): void
    {
        $results = $this->race([[50000, 'mesma'], [60000, 'mesma']]);

        $this->assertEqualsCanonicalizing(['created', 'conflict'], array_column($results, 'result'));
        $this->assertSame(1, Receipt::query()->where('space_id', $this->space->id)->count());
    }

    private function recordReceipt(int $cents, string $key): int
    {
        return app(ReceiveInstallment::class)->handle($this->user, $this->space, $this->installment->id, $this->account->id, $cents, '2026-02-10', $key)->receiptId;
    }

    /** @return list<string> */
    private function receiveWorker(int $cents, string $date, string $key): array
    {
        return ['tests/Support/receive_worker.php', (string) $this->user->id, (string) $this->space->id,
            (string) $this->installment->id, (string) $this->account->id, (string) $cents, $date, $key];
    }

    /** @return list<string> */
    private function accountWorker(string $operation, string ...$arguments): array
    {
        return ['tests/Support/account_worker.php', $operation, (string) $this->user->id, (string) $this->space->id, (string) $this->account->id, ...$arguments];
    }

    /** @return list<string> */
    private function reverseWorker(int $receipt, string $key, array $replacement = []): array
    {
        return ['tests/Support/reverse_worker.php', (string) $this->user->id, (string) $this->space->id, (string) $receipt, $key, 'Disputa', ...$replacement];
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
        return $this->raceWorkers(array_map(fn (array $request) => ['tests/Support/receive_worker.php',
            (string) $this->user->id, (string) $this->space->id, (string) $this->installment->id,
            (string) $this->account->id, (string) $request[0], '2026-02-10', $request[1],
        ], $requests));
    }

    /**
     * Mesma disputa com workers arbitrários: [script, ...argumentos].
     *
     * @param  list<list<string>>  $commands
     * @return list<array<string, mixed>>
     */
    private function raceWorkers(array $commands): array
    {
        // Ajuste de abertura e arquivamento travam só a conta.
        return $this->raceProcesses($commands, [['installments', $this->installment->id], ['accounts', $this->account->id]]);
    }
}
