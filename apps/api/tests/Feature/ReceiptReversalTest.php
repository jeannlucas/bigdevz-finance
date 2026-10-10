<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\IdempotencyKey;
use App\Models\Installment;
use App\Models\Receipt;
use App\Models\ReceiptReversal;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Illuminate\Testing\TestResponse;
use RuntimeException;
use Tests\TestCase;

/** Estorno e correção de recebimentos, em PostgreSQL real de testes. */
class ReceiptReversalTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    private int $a;

    private int $b;

    /** @var list<int> */
    private array $installments;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->login($this->user);
        $this->a = $this->account($this->pf, 'Conta A', '1000.00', '2026-01-01');
        $this->b = $this->account($this->pf, 'Conta B', '0.00', '2026-01-01');
        $agreement = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Venda de veículo', 'total' => '24000.00', 'installment_count' => 12, 'first_due_date' => '2026-02-10',
        ])->assertCreated()->json('data.id');
        $this->installments = array_column($this->api('GET', "/api/spaces/{$this->pf->id}/agreements/{$agreement}")->json('data.installments'), 'id');
    }

    public function test_reversal_compensates_once_keeps_history_and_replays(): void
    {
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec-1')->assertCreated()->json('data.receipt.id');

        $this->reverse($receipt, 'Lançado por engano', 'est-1')
            ->assertCreated()
            ->assertJsonPath('data.reversal.kind', 'reversal')
            ->assertJsonPath('data.reversal.reason', 'Lançado por engano')
            ->assertJsonPath('data.reversal.user_id', $this->user->id)
            ->assertJsonPath('data.original.id', $receipt)
            ->assertJsonPath('data.original.status', 'reversed')
            ->assertJsonPath('data.replacement', null)
            ->assertJsonPath('data.installment.remaining', '2000.00')
            ->assertJsonPath('data.installment.status', 'pending')
            ->assertJsonPath('data.accounts.0.balance', '1000.00')
            ->assertJsonPath('idempotency.status', 'completed');

        // Original e sua movimentação intactos; compensação na data do original.
        $original = Receipt::query()->findOrFail($receipt);
        $this->assertSame(50000, $original->amount_cents);
        $this->assertSame(50000, $original->movement->amount_cents);
        $reversal = ReceiptReversal::query()->where('receipt_id', $receipt)->sole();
        $this->assertNotNull($reversal->created_at);
        $this->assertSame(-50000, $reversal->movement->amount_cents);
        $this->assertSame('2026-02-10', $reversal->movement->effective_date->toDateString());

        // Mesma chave: mesmo estorno, sem segunda compensação.
        $this->reverse($receipt, 'Lançado por engano', 'est-1')
            ->assertOk()->assertJsonPath('data.reversal.id', $reversal->id)->assertJsonPath('data.replayed', true);
        // Outra chave sobre o mesmo recebimento: recusa registrada.
        $this->reverse($receipt, 'De novo', 'est-2')
            ->assertStatus(422)->assertJsonValidationErrors('receipt')
            ->assertJsonPath('idempotency.status', 'rejected');
        // Chave do recebimento original: devolve o original, agora estornado.
        $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec-1')
            ->assertOk()
            ->assertJsonPath('data.receipt.id', $receipt)
            ->assertJsonPath('data.receipt.status', 'reversed')
            ->assertJsonPath('data.account.balance', '1000.00');

        $this->assertSame(1, ReceiptReversal::query()->where('space_id', $this->pf->id)->count());
        $this->assertSame(2, AccountMovement::query()->where('account_id', $this->a)->count());
        $this->assertBalance($this->a, '1000.00');
        $this->api('GET', "/api/spaces/{$this->pf->id}/summary")
            ->assertJsonPath('data.balance', '1000.00')
            ->assertJsonPath('data.received_total', '0.00')
            ->assertJsonPath('data.receivable_remaining', '24000.00');
    }

    /** Exemplo 1: conta errada. */
    public function test_correction_moves_receipt_to_another_account(): void
    {
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');

        $response = $this->correct($receipt, $this->b, '500.00', '2026-02-10', 'Conta errada', 'cor')
            ->assertCreated()
            ->assertJsonPath('data.reversal.kind', 'correction')
            ->assertJsonPath('data.original.status', 'reversed')
            ->assertJsonPath('data.replacement.account_id', $this->b)
            ->assertJsonPath('data.replacement.status', 'active')
            ->assertJsonPath('data.replacement.replaces_receipt_id', $receipt)
            ->assertJsonPath('data.installment.remaining', '1500.00')
            ->assertJsonCount(2, 'data.accounts');
        $replacement = $response->json('data.replacement.id');
        $this->assertSame($replacement, ReceiptReversal::query()->where('receipt_id', $receipt)->sole()->replacement_receipt_id);

        $this->assertBalance($this->a, '1000.00');
        $this->assertBalance($this->b, '500.00');
        // Resposta perdida: a mesma chave devolve a mesma correção.
        $this->correct($receipt, $this->b, '500.00', '2026-02-10', 'Conta errada', 'cor')
            ->assertOk()->assertJsonPath('data.replacement.id', $replacement);
        $this->assertBalance($this->b, '500.00');
        $this->assertSame(2, Receipt::query()->where('space_id', $this->pf->id)->count());
        $this->assertSame(3, AccountMovement::query()->whereIn('account_id', [$this->a, $this->b])->count());
    }

    /** Exemplo 2: valor errado na mesma conta. */
    public function test_correction_of_amount_applies_only_the_difference(): void
    {
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');

        $this->correct($receipt, $this->a, '400.00', '2026-02-10', 'Valor errado', 'cor')
            ->assertCreated()
            ->assertJsonPath('data.installment.remaining', '1600.00')
            ->assertJsonPath('data.accounts.0.balance', '1400.00');
        $this->assertBalance($this->a, '1400.00');
    }

    /** Exemplo 4: só a data; o saldo final não muda e a trilha fica. */
    public function test_correction_of_date_only_keeps_balance_and_dates(): void
    {
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');

        $replacement = $this->correct($receipt, $this->a, '500.00', '2026-02-12', 'Data errada', 'cor')
            ->assertCreated()->json('data.replacement.id');

        $this->assertBalance($this->a, '1500.00');
        $reversal = ReceiptReversal::query()->where('receipt_id', $receipt)->sole();
        $this->assertSame('2026-02-10', $reversal->movement->effective_date->toDateString());
        $this->assertSame('2026-02-10', Receipt::query()->findOrFail($receipt)->received_on->toDateString());
        $this->assertSame('2026-02-12', Receipt::query()->findOrFail($replacement)->movement->effective_date->toDateString());
    }

    public function test_replacement_can_be_corrected_again_but_reversed_original_cannot(): void
    {
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');
        $first = $this->correct($receipt, $this->b, '500.00', '2026-02-10', 'Conta errada', 'cor-1')->json('data.replacement.id');

        $this->correct($receipt, $this->a, '450.00', '2026-02-10', 'De novo', 'cor-2')
            ->assertStatus(422)->assertJsonValidationErrors('receipt');
        $second = $this->correct($first, $this->b, '450.00', '2026-02-10', 'Valor errado', 'cor-3')
            ->assertCreated()->assertJsonPath('data.replacement.replaces_receipt_id', $first)->json('data.replacement.id');

        $receipts = $this->api('GET', "/api/spaces/{$this->pf->id}/installments/{$this->installments[0]}")
            ->assertJsonPath('data.received', '450.00')->json('data.receipts');
        $this->assertSame(
            [[$receipt, 'reversed', null], [$first, 'reversed', $receipt], [$second, 'active', $first]],
            array_map(fn ($r) => [$r['id'], $r['status'], $r['replaces_receipt_id']], $receipts),
        );
        $this->assertBalance($this->a, '1000.00');
        $this->assertBalance($this->b, '450.00');
    }

    /** Exemplo 3 e limites de valor com outros recebimentos na parcela. */
    public function test_correction_limits_and_state_with_other_receipts(): void
    {
        $other = $this->receive(0, $this->a, '1200.00', '2026-02-10', 'outro')->json('data.receipt.id');
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');
        $this->assertSame('300.00', $this->installment(0)['remaining']);

        $this->correct($receipt, $this->a, '800.01', '2026-02-10', 'Valor', 'acima')
            ->assertStatus(422)->assertJsonValidationErrors('amount')->assertJsonPath('idempotency.status', 'rejected');
        $this->correct($receipt, $this->a, '500.00', '2026-02-10', 'Nada', 'igual')
            ->assertStatus(422)->assertJsonValidationErrors('receipt');
        $this->correct($receipt, $this->a, '800.00', '2026-02-10', 'Faltava', 'quita')
            ->assertCreated()->assertJsonPath('data.installment.status', 'paid');
        $this->api('GET', "/api/spaces/{$this->pf->id}/agreements")->assertJsonPath('data.0.paid_installments', 1);

        // Exemplo 3: recebimento inexistente, só estorno; reabre a parcela.
        $this->reverse($other, 'Não existiu', 'est')
            ->assertCreated()->assertJsonPath('data.installment.remaining', '1200.00')->assertJsonPath('data.installment.status', 'partial');
        $this->assertBalance($this->a, '1800.00');
        $this->api('GET', "/api/spaces/{$this->pf->id}/summary")
            ->assertJsonPath('data.received_total', '800.00')
            ->assertJsonPath('data.receivable_remaining', '23200.00');
        $this->api('GET', "/api/spaces/{$this->pf->id}/agreements")->assertJsonPath('data.0.paid_installments', 0);
    }

    public function test_dates_respect_opening_balance_and_today(): void
    {
        $late = $this->account($this->pf, 'Aberta depois', '0.00', '2026-02-11');
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');

        $this->correct($receipt, $late, '500.00', '2026-02-10', 'Conta', 'antes')
            ->assertStatus(422)->assertJsonValidationErrors('received_on');
        $this->correct($receipt, $this->a, '500.00', now('America/Sao_Paulo')->addDay()->toDateString(), 'Data', 'futuro')
            ->assertStatus(422)->assertJsonValidationErrors('received_on');
        $this->correct($receipt, $late, '500.00', '2026-02-11', 'Conta', 'no-limite')->assertCreated();
        $this->assertBalance($late, '500.00');
        $this->assertSame(0, AccountMovement::query()->where('account_id', $late)->where('effective_date', '<', '2026-02-11')->count());
    }

    public function test_reason_and_payload_are_validated_and_recorded(): void
    {
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');

        $this->reverse($receipt, '', 'sem-motivo')->assertStatus(422)->assertJsonValidationErrors('reason')
            ->assertJsonPath('idempotency.status', 'rejected');
        $this->correct($receipt, $this->a, '400,00', '2026-02-10', 'Valor', 'formato')->assertStatus(422)->assertJsonValidationErrors('amount');
        $this->withToken($this->token)->postJson("/api/spaces/{$this->pf->id}/receipts/{$receipt}/reversal", ['reason' => 'Sem chave'])
            ->assertStatus(422)->assertJsonValidationErrors('idempotency_key')->assertJsonMissingPath('idempotency');
        // Mesma chave com outro conteúdo: conflito.
        $this->reverse($receipt, 'Outro motivo', 'sem-motivo')->assertStatus(409);

        $this->assertSame(0, ReceiptReversal::query()->where('space_id', $this->pf->id)->count());
        $this->assertBalance($this->a, '1500.00');
    }

    public function test_spaces_and_users_are_isolated(): void
    {
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');
        $pjAccount = $this->account($this->pj, 'PJ', '0.00', '2026-01-01');

        $this->correct($receipt, $pjAccount, '500.00', '2026-02-10', 'Conta PJ', 'pj')
            ->assertStatus(422)->assertJsonValidationErrors('account_id');
        $this->withToken($this->token)->postJson("/api/spaces/{$this->pj->id}/receipts/{$receipt}/reversal", ['reason' => 'Pelo PJ'], ['Idempotency-Key' => 'x'])
            ->assertNotFound();

        [$intruder, $intruderPf] = $this->userWithSpaces();
        $this->app['auth']->forgetGuards();
        $intruderToken = $this->login($intruder);
        $this->withToken($intruderToken)->postJson("/api/spaces/{$this->pf->id}/receipts/{$receipt}/reversal", ['reason' => 'Alheio'], ['Idempotency-Key' => 'y'])
            ->assertNotFound();
        $this->withToken($intruderToken)->postJson("/api/spaces/{$intruderPf->id}/receipts/{$receipt}/correction", [
            'reason' => 'Alheio', 'account_id' => $this->a, 'amount' => '1.00', 'received_on' => '2026-02-10',
        ], ['Idempotency-Key' => 'z'])->assertNotFound();

        $this->assertSame(0, ReceiptReversal::query()->where('receipt_id', $receipt)->count());
        $this->assertSame(0, IdempotencyKey::query()->whereIn('key', ['x', 'y', 'z'])->count(), '404 não registra decisão');
        $this->app['auth']->forgetGuards();
        $this->assertBalance($this->a, '1500.00');
    }

    public function test_failure_inside_correction_rolls_back_everything(): void
    {
        $receipt = $this->receive(0, $this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');
        Receipt::creating(static fn () => throw new RuntimeException('falha simulada no substituto'));

        $this->withoutExceptionHandling();
        try {
            $this->correct($receipt, $this->b, '500.00', '2026-02-10', 'Conta errada', 'falha');
            $this->fail('A falha simulada deveria interromper a correção.');
        } catch (RuntimeException $error) {
            $this->assertSame('falha simulada no substituto', $error->getMessage());
        } finally {
            Receipt::flushEventListeners();
        }

        $this->assertSame(0, ReceiptReversal::query()->where('space_id', $this->pf->id)->count());
        $this->assertSame(1, AccountMovement::query()->whereIn('account_id', [$this->a, $this->b])->count());
        $this->assertSame(50000, $this->installmentModel(0)->received_cents);
        $this->assertBalance($this->a, '1500.00');
        $this->assertBalance($this->b, '0.00');
        $this->assertSame(0, IdempotencyKey::query()->where('key', 'falha')->count(), 'falha não decide a chave');

        $this->correct($receipt, $this->b, '500.00', '2026-02-10', 'Conta errada', 'falha')->assertCreated();
        $this->assertBalance($this->b, '500.00');
    }

    /** Item 7: uma recusa persistida não vira aceite quando um estorno reabre a parcela. */
    public function test_rejected_key_stays_rejected_after_reversal_reopens_installment(): void
    {
        $paid = $this->receive(0, $this->a, '2000.00', '2026-02-10', 'quita')->json('data.receipt.id');
        $this->receive(0, $this->a, '100.00', '2026-02-10', 'recusada')
            ->assertStatus(422)->assertJsonPath('idempotency.status', 'rejected')->assertJsonPath('idempotency.replayed', false);

        $this->reverse($paid, 'Não recebido', 'reabre')->assertCreated()->assertJsonPath('data.installment.remaining', '2000.00');

        $this->receive(0, $this->a, '100.00', '2026-02-10', 'recusada')
            ->assertStatus(422)->assertJsonValidationErrors('amount')
            ->assertJsonPath('idempotency.status', 'rejected')->assertJsonPath('idempotency.replayed', true);
        $this->assertSame(0, Receipt::query()->where('idempotency_key', 'recusada')->count());

        $this->receive(0, $this->a, '100.00', '2026-02-10', 'nova-intencional')->assertCreated();
        $this->assertBalance($this->a, '1100.00');
    }

    /** Recusa por data futura continua recusada depois que a data passa. */
    public function test_request_rejection_is_bound_to_the_key_over_time(): void
    {
        $tomorrow = now('America/Sao_Paulo')->addDay()->toDateString();
        $this->receive(0, $this->a, '100.00', $tomorrow, 'amanha')->assertStatus(422)->assertJsonValidationErrors('received_on');

        Carbon::setTestNow(now()->addDays(2));
        try {
            $this->receive(0, $this->a, '100.00', $tomorrow, 'amanha')
                ->assertStatus(422)->assertJsonPath('idempotency.replayed', true);
            $this->receive(0, $this->a, '100.00', $tomorrow, 'outra')->assertCreated();
        } finally {
            Carbon::setTestNow();
        }
        $this->assertSame(1, Receipt::query()->where('space_id', $this->pf->id)->count());
    }

    private function login(User $user): string
    {
        return $this->postJson('/api/auth/login', ['email' => $user->email, 'password' => 'password', 'device_name' => 'teste'])
            ->assertOk()->json('token');
    }

    private function api(string $method, string $uri, array $data = [], array $headers = []): TestResponse
    {
        return $this->withToken($this->token)->json($method, $uri, $data, $headers);
    }

    private function account(Space $space, string $name, string $opening, string $date): int
    {
        return $this->api('POST', "/api/spaces/{$space->id}/accounts", [
            'name' => $name, 'opening_balance' => $opening, 'opening_balance_date' => $date,
        ])->assertCreated()->json('data.id');
    }

    private function receive(int $index, int $account, string $amount, string $date, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/installments/{$this->installments[$index]}/receipts", [
            'account_id' => $account, 'amount' => $amount, 'received_on' => $date,
        ], ['Idempotency-Key' => $key]);
    }

    private function reverse(int $receipt, string $reason, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/receipts/{$receipt}/reversal", ['reason' => $reason], ['Idempotency-Key' => $key]);
    }

    private function correct(int $receipt, int $account, string $amount, string $date, string $reason, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/receipts/{$receipt}/correction", [
            'reason' => $reason, 'account_id' => $account, 'amount' => $amount, 'received_on' => $date,
        ], ['Idempotency-Key' => $key]);
    }

    private function installment(int $index): array
    {
        return $this->api('GET', "/api/spaces/{$this->pf->id}/installments/{$this->installments[$index]}")->json('data');
    }

    private function installmentModel(int $index): Installment
    {
        return Installment::query()->findOrFail($this->installments[$index]);
    }

    private function assertBalance(int $account, string $expected): void
    {
        $this->api('GET', "/api/spaces/{$this->pf->id}/accounts/{$account}")->assertJsonPath('data.balance', $expected);
    }
}
