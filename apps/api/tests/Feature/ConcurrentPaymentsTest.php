<?php

namespace Tests\Feature;

use App\Actions\Payables\CreatePayable;
use App\Actions\Payables\GenerateObligations;
use App\Actions\Payables\PayPayable;
use App\Actions\Receivables\CreateAgreement;
use App\Models\Account;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\Recurrence;
use App\Models\Space;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\RacesProcesses;
use Tests\TestCase;

/**
 * A pagar com processos e conexões PostgreSQL reais disputando obrigação e
 * conta. Confere quantidades e somas, não só o resultado de cada processo.
 */
class ConcurrentPaymentsTest extends TestCase
{
    use RacesProcesses;

    private User $user;

    private Space $space;

    private Account $account;

    private Payable $payable;

    protected function setUp(): void
    {
        parent::setUp();
        $this->user = User::factory()->create();
        $this->space = $this->user->spaces()->where('kind', 'PF')->firstOrFail();
        $this->account = $this->space->accounts()->create([
            'name' => 'Conta', 'opening_balance_cents' => 100000, 'opening_balance_date' => '2026-01-01',
        ]);
        $this->payable = Payable::create([
            'space_id' => $this->space->id, 'kind' => Payable::SINGLE, 'description' => 'Despesa',
            'amount_cents' => 30000, 'due_date' => '2026-03-20',
        ]);
    }

    protected function tearDown(): void
    {
        $space = $this->space->id;
        DB::table('idempotency_keys')->where('space_id', $space)->delete();
        DB::table('account_movements')->where('account_id', $this->account->id)->delete();
        DB::table('payment_reversals')->where('space_id', $space)->delete();
        DB::table('payments')->where('space_id', $space)->delete();
        DB::table('receipts')->where('space_id', $space)->delete();
        DB::table('account_opening_adjustments')->where('space_id', $space)->delete();
        DB::table('obligation_changes')->where('space_id', $space)->delete();
        DB::table('payables')->where('space_id', $space)->delete();
        DB::table('payable_plans')->where('space_id', $space)->delete();
        DB::table('recurrences')->where('space_id', $space)->delete();
        DB::table('installments')->where('space_id', $space)->delete();
        DB::table('agreements')->where('space_id', $space)->delete();
        DB::table('accounts')->where('space_id', $space)->delete();
        DB::table('spaces')->where('user_id', $this->user->id)->delete();
        DB::table('users')->where('id', $this->user->id)->delete();
        parent::tearDown();
    }

    public function test_simultaneous_payments_cannot_exceed_the_obligation(): void
    {
        $results = $this->race([$this->pay(20000, 'a'), $this->pay(20000, 'b')]);

        $this->assertEqualsCanonicalizing(['created', 'rejected'], array_column($results, 'result'));
        $this->assertSame(20000, $this->payable->fresh()->paid_cents);
        $this->assertSame(1, Payment::query()->where('payable_id', $this->payable->id)->count());
        $this->assertSame(1, DB::table('account_movements')->where('account_id', $this->account->id)->count());
        $this->assertSame(80000, $this->account->fresh()->balanceCents());
    }

    public function test_same_key_payment_is_applied_once(): void
    {
        $results = $this->race([$this->pay(10000, 'mesma'), $this->pay(10000, 'mesma')]);

        $this->assertEqualsCanonicalizing(['created', 'replayed'], array_column($results, 'result'));
        $this->assertSame(1, Payment::query()->where('payable_id', $this->payable->id)->count());
        $this->assertSame(90000, $this->account->fresh()->balanceCents());
    }

    public function test_correction_and_new_payment_cannot_exceed_the_obligation(): void
    {
        $payment = app(PayPayable::class)->handle($this->user, $this->space, $this->payable->id, $this->account->id, 10000, '2026-03-10', 'base')->ref('payment_id');
        $results = $this->race([
            ['tests/Support/payable_worker.php', 'correct', (string) $this->user->id, (string) $this->space->id, (string) $payment, 'corrige', (string) $this->account->id, '25000', '2026-03-10'],
            $this->pay(15000, 'nova'),
        ]);

        $this->assertEqualsCanonicalizing(['created', 'rejected'], array_column($results, 'result'));
        $paid = $this->payable->fresh()->paid_cents;
        $this->assertSame(25000, $paid);
        $this->assertSame(100000 - $paid, $this->account->fresh()->balanceCents());
    }

    public function test_outflow_and_inflow_on_the_same_account_both_count_once(): void
    {
        $installment = app(CreateAgreement::class)->handle($this->space, 'Venda', '500.00', 1, '2026-02-10')->installments()->firstOrFail();
        $results = $this->race([
            $this->pay(10000, 'saida'),
            ['tests/Support/receive_worker.php', (string) $this->user->id, (string) $this->space->id, (string) $installment->id,
                (string) $this->account->id, '50000', '2026-02-10', 'entrada'],
        ], [['installments', $installment->id]]);

        $this->assertSame(['created', 'created'], array_column($results, 'result'));
        $this->assertSame(2, DB::table('account_movements')->where('account_id', $this->account->id)->count());
        $this->assertSame(100000 - 10000 + 50000, $this->account->fresh()->balanceCents());
    }

    public function test_payment_and_opening_adjustment_keep_exact_balance(): void
    {
        $results = $this->race([
            $this->pay(10000, 'paga'),
            ['tests/Support/account_worker.php', 'adjust', (string) $this->user->id, (string) $this->space->id, (string) $this->account->id, '200000', '2026-01-01', 'abre'],
        ]);

        $this->assertSame(['created', 'created'], array_column($results, 'result'));
        $this->assertSame(200000 - 10000, $this->account->fresh()->balanceCents());
    }

    public function test_simultaneous_generation_creates_each_cycle_once(): void
    {
        $result = app(CreatePayable::class)->recurrence($this->user, $this->space, [
            'description' => 'Aluguel', 'payee' => null, 'amount' => '1500.00', 'start_date' => '2026-01-31', 'end_date' => null,
            'approved_until' => GenerateObligations::horizon(), 'confirm_past' => true,
        ], 'aluguel', 'fp');
        $recurrence = Recurrence::query()->findOrFail($result->ref('recurrence_id'));
        $expected = Payable::query()->where('recurrence_id', $recurrence->id)->count();
        // Remove os ciclos a partir do terceiro para os dois processos disputarem a recriação.
        Payable::query()->where('recurrence_id', $recurrence->id)->where('cycle', '>', '2026-02-01')->delete();

        $results = $this->raceProcesses([['artisan', 'payables:generate'], ['artisan', 'payables:generate']], [['recurrences', $recurrence->id]]);

        $this->assertCount(2, $results);
        $this->assertSame($expected, Payable::query()->where('recurrence_id', $recurrence->id)->count());
        $this->assertSame($expected, Payable::query()->where('recurrence_id', $recurrence->id)->distinct()->count('cycle'));
    }

    public function test_same_key_creation_in_flight_creates_one_set(): void
    {
        foreach ([
            'parcelas' => ['kind' => 'installment', 'description' => 'Notebook', 'payee' => null, 'total' => '100.00', 'installment_count' => 3, 'first_due_date' => '2026-04-10'],
            'recorrente' => ['kind' => 'recurring', 'description' => 'Aluguel', 'payee' => null, 'amount' => '1500.00', 'start_date' => '2026-01-31',
                'end_date' => null, 'approved_until' => GenerateObligations::horizon(), 'confirm_past' => true],
        ] as $key => $data) {
            $command = ['tests/Support/payable_worker.php', 'create', (string) $this->user->id, (string) $this->space->id, '0', $key, json_encode($data)];
            $results = $this->raceProcesses([$command, $command], [['advisory', "idempotency:{$this->space->id}:{$key}"]]);
            $this->assertEqualsCanonicalizing(['created', 'replayed'], array_column($results, 'result'), $key);
        }

        $this->assertSame(1, DB::table('payable_plans')->where('space_id', $this->space->id)->count());
        $this->assertSame(3, Payable::query()->where('space_id', $this->space->id)->whereNotNull('plan_id')->count());
        $recurrence = Recurrence::query()->where('space_id', $this->space->id)->sole();
        $expected = count(GenerateObligations::recurrenceCycles('2026-01-31', 31, null, $recurrence->initial_until->toDateString()));
        $this->assertSame($expected, Payable::query()->where('recurrence_id', $recurrence->id)->count());
        $this->assertSame(2, DB::table('idempotency_keys')->where('space_id', $this->space->id)->count());
    }

    /** @param list<array{0: string, 1: int}> $extra */
    private function race(array $commands, array $extra = []): array
    {
        return $this->raceProcesses($commands, [['payables', $this->payable->id], ['accounts', $this->account->id], ...$extra]);
    }

    /** @return list<string> */
    private function pay(int $cents, string $key): array
    {
        return ['tests/Support/payable_worker.php', 'pay', (string) $this->user->id, (string) $this->space->id,
            (string) $this->payable->id, $key, (string) $this->account->id, (string) $cents, '2026-03-10'];
    }
}
