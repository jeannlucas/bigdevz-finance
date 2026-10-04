<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class ReceivablesFlowTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->postJson('/api/auth/login', [
            'email' => $this->user->email,
            'password' => 'password',
            'device_name' => 'teste',
        ])->assertOk()->json('token');
    }

    public function test_login_lists_only_own_pf_and_pj_spaces(): void
    {
        $this->api('GET', '/api/spaces')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.kind', 'PF')
            ->assertJsonPath('data.1.kind', 'PJ');
    }

    public function test_invalid_login_and_missing_token_are_rejected(): void
    {
        $this->postJson('/api/auth/login', ['email' => $this->user->email, 'password' => 'errada', 'device_name' => 'x'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('email');
        $this->getJson('/api/spaces')->assertUnauthorized();
    }

    public function test_logout_revokes_current_token(): void
    {
        $this->api('POST', '/api/auth/logout')->assertNoContent();
        $this->app['auth']->forgetGuards();
        $this->api('GET', '/api/spaces')->assertUnauthorized();
    }

    /** Cenários 1, 2, 3 e 4 da seção 7.E. */
    public function test_main_scenario_installments_partial_receipts_and_replay(): void
    {
        $account = $this->createAccount($this->pf, '1000.00', '2026-01-01');
        $agreement = $this->createAgreement($this->pf, '24000.00', 12, '2026-02-10');

        // 1. Doze parcelas de R$ 2.000,00; cadastrar o acordo não altera saldo.
        $installments = $this->api('GET', "/api/spaces/{$this->pf->id}/agreements/{$agreement}")
            ->assertOk()
            ->assertJsonPath('data.total', '24000.00')
            ->assertJsonPath('data.remaining', '24000.00')
            ->json('data.installments');
        $this->assertCount(12, $installments);
        $this->assertSame(array_fill(0, 12, '2000.00'), array_column($installments, 'amount'));
        $this->assertSame(range(1, 12), array_column($installments, 'number'));
        $this->assertBalance($account, '1000.00');

        // 2. Primeira parcela quitada.
        $this->receive($installments[0]['id'], $account, '2000.00', '2026-02-10', 'chave-1')
            ->assertCreated()
            ->assertJsonPath('data.installment.status', 'paid')
            ->assertJsonPath('data.agreement.remaining', '22000.00')
            ->assertJsonPath('data.agreement.paid_installments', 1)
            ->assertJsonPath('data.account.balance', '3000.00');
        $this->assertBalance($account, '3000.00');

        // 3. Segunda parcela parcial.
        $first = $this->receive($installments[1]['id'], $account, '500.00', '2026-03-10', 'chave-2')
            ->assertCreated()
            ->assertJsonPath('data.installment.status', 'partial')
            ->assertJsonPath('data.installment.remaining', '1500.00')
            ->assertJsonPath('data.agreement.remaining', '21500.00')
            ->assertJsonPath('data.agreement.received', '2500.00')
            ->assertJsonPath('data.account.balance', '3500.00');

        // 4. Reenvio idêntico devolve o mesmo recebimento, sem nova movimentação.
        $this->receive($installments[1]['id'], $account, '500.00', '2026-03-10', 'chave-2')
            ->assertOk()
            ->assertJsonPath('data.receipt.id', $first->json('data.receipt.id'))
            ->assertJsonPath('data.account.balance', '3500.00');
        $this->assertBalance($account, '3500.00');
        $this->assertSame(2, Receipt::query()->where('space_id', $this->pf->id)->count());
        $this->assertSame(2, AccountMovement::query()->where('account_id', $account)->count());

        // Consulta posterior (app reaberto) recupera o estado pela API.
        $this->api('GET', "/api/spaces/{$this->pf->id}/installments/{$installments[1]['id']}")
            ->assertOk()
            ->assertJsonPath('data.received', '500.00')
            ->assertJsonPath('data.remaining', '1500.00')
            ->assertJsonCount(1, 'data.receipts');
        $this->api('GET', "/api/spaces/{$this->pf->id}/summary")
            ->assertOk()
            ->assertJsonPath('data.balance', '3500.00')
            ->assertJsonPath('data.receivable_remaining', '21500.00');
    }

    /** Cenário 11, segunda parte: chave reutilizada com outro conteúdo. */
    public function test_reused_idempotency_key_with_different_payload_conflicts(): void
    {
        $account = $this->createAccount($this->pf, '1000.00', '2026-01-01');
        $agreement = $this->createAgreement($this->pf, '24000.00', 12, '2026-02-10');
        $ids = $this->installmentIds($agreement);

        $this->receive($ids[0], $account, '500.00', '2026-02-10', 'mesma-chave')->assertCreated();
        $this->receive($ids[0], $account, '600.00', '2026-02-10', 'mesma-chave')->assertStatus(409);
        $this->receive($ids[1], $account, '500.00', '2026-02-10', 'mesma-chave')->assertStatus(409);
        $this->assertBalance($account, '1500.00');
        $this->assertSame(1, Receipt::query()->where('space_id', $this->pf->id)->count());
    }

    public function test_receipt_cannot_exceed_installment_remaining(): void
    {
        $account = $this->createAccount($this->pf, '0.00', '2026-01-01');
        $ids = $this->installmentIds($this->createAgreement($this->pf, '24000.00', 12, '2026-02-10'));

        $this->receive($ids[0], $account, '1500.00', '2026-02-10', 'a')->assertCreated();
        $this->receive($ids[0], $account, '500.01', '2026-02-10', 'b')
            ->assertStatus(422)
            ->assertJsonValidationErrors('amount');
        $this->receive($ids[0], $account, '500.00', '2026-02-10', 'c')->assertCreated();
        $this->receive($ids[0], $account, '0.01', '2026-02-10', 'd')->assertStatus(422);
        $this->assertBalance($account, '2000.00');
    }

    public function test_receipt_validates_money_dates_and_key(): void
    {
        $account = $this->createAccount($this->pf, '1000.00', '2026-01-10');
        $ids = $this->installmentIds($this->createAgreement($this->pf, '300.00', 3, '2026-02-10'));

        foreach (['100,00', '100', '-1.00', '0.00', '1.001', 100.5, 100] as $amount) {
            $this->receive($ids[0], $account, $amount, '2026-02-10', 'k-'.md5((string) $amount))
                ->assertStatus(422)
                ->assertJsonValidationErrors('amount');
        }
        // Antes do marco do saldo inicial da conta.
        $this->receive($ids[0], $account, '10.00', '2026-01-09', 'antes')->assertStatus(422)->assertJsonValidationErrors('received_on');
        // Data futura não é recebimento efetivado.
        $this->receive($ids[0], $account, '10.00', now('America/Sao_Paulo')->addDay()->toDateString(), 'futuro')
            ->assertStatus(422)->assertJsonValidationErrors('received_on');
        $this->receive($ids[0], $account, '10.00', '2026-02-30', 'invalida')->assertStatus(422)->assertJsonValidationErrors('received_on');
        // Chave idempotente obrigatória.
        $this->api('POST', "/api/spaces/{$this->pf->id}/installments/{$ids[0]}/receipts", [
            'account_id' => $account, 'amount' => '10.00', 'received_on' => '2026-02-10',
        ])->assertStatus(422)->assertJsonValidationErrors('idempotency_key');

        $this->assertBalance($account, '1000.00');
        $this->assertSame(0, Receipt::query()->where('space_id', $this->pf->id)->count());
    }

    /** Cenário 8. */
    public function test_hundred_in_three_installments_keeps_exact_total(): void
    {
        $agreement = $this->createAgreement($this->pf, '100.00', 3, '2026-01-31');
        $installments = $this->api('GET', "/api/spaces/{$this->pf->id}/agreements/{$agreement}")->json('data.installments');

        $this->assertSame(['33.34', '33.33', '33.33'], array_column($installments, 'amount'));
        // Cenário 9: dia 31 vira 28/02 e volta a 31/03.
        $this->assertSame(['2026-01-31', '2026-02-28', '2026-03-31'], array_column($installments, 'due_date'));
    }

    public function test_agreement_and_account_validation(): void
    {
        $base = "/api/spaces/{$this->pf->id}";
        $this->api('POST', "$base/agreements", ['description' => 'X', 'total' => '0.01', 'installment_count' => 2, 'first_due_date' => '2026-01-01'])
            ->assertStatus(422)->assertJsonValidationErrors('installment_count');
        $this->api('POST', "$base/agreements", ['description' => 'X', 'total' => '1000000000000.00', 'installment_count' => 1, 'first_due_date' => '2026-01-01'])
            ->assertStatus(422)->assertJsonValidationErrors('total');
        $this->api('POST', "$base/agreements", ['description' => '', 'total' => '10.00', 'installment_count' => 1, 'first_due_date' => '2026-02-31'])
            ->assertStatus(422)->assertJsonValidationErrors(['description', 'first_due_date']);
        $this->api('POST', "$base/accounts", ['name' => 'Conta', 'opening_balance' => 1000.0, 'opening_balance_date' => '2026-01-01'])
            ->assertStatus(422)->assertJsonValidationErrors('opening_balance');
        $this->assertSame(0, $this->pf->agreements()->count());
        $this->assertSame(0, $this->pf->accounts()->count());
    }

    public function test_account_balance_cannot_overflow_documented_limit(): void
    {
        $account = $this->createAccount($this->pf, '999999999999.00', '2026-01-01');
        $ids = $this->installmentIds($this->createAgreement($this->pf, '10.00', 1, '2026-02-10'));

        $this->receive($ids[0], $account, '10.00', '2026-02-10', 'limite')
            ->assertStatus(422)
            ->assertJsonValidationErrors('amount');
        $this->assertBalance($account, '999999999999.00');
    }

    public function test_spaces_keep_data_separate(): void
    {
        $this->createAccount($this->pf, '1000.00', '2026-01-01');
        $this->createAgreement($this->pf, '24000.00', 12, '2026-02-10');
        $this->createAccount($this->pj, '50.00', '2026-01-01');

        $this->api('GET', "/api/spaces/{$this->pj->id}/accounts")->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.balance', '50.00');
        $this->api('GET', "/api/spaces/{$this->pj->id}/agreements")->assertOk()->assertJsonCount(0, 'data');
        $this->api('GET', "/api/spaces/{$this->pj->id}/summary")->assertJsonPath('data.balance', '50.00')->assertJsonPath('data.receivable_remaining', '0.00');
        $this->api('GET', "/api/spaces/{$this->pf->id}/summary")->assertJsonPath('data.balance', '1000.00')->assertJsonPath('data.receivable_remaining', '24000.00');
    }

    protected function api(string $method, string $uri, array $data = [], array $headers = []): TestResponse
    {
        return $this->withToken($this->token)->json($method, $uri, $data, $headers);
    }

    protected function createAccount(Space $space, string $opening, string $date): int
    {
        return $this->api('POST', "/api/spaces/{$space->id}/accounts", [
            'name' => 'Conta '.$space->kind, 'opening_balance' => $opening, 'opening_balance_date' => $date,
        ])->assertCreated()->assertJsonPath('data.balance', $opening)->json('data.id');
    }

    protected function createAgreement(Space $space, string $total, int $count, string $firstDue): int
    {
        return $this->api('POST', "/api/spaces/{$space->id}/agreements", [
            'description' => 'Venda de veículo', 'total' => $total, 'installment_count' => $count, 'first_due_date' => $firstDue,
        ])->assertCreated()->assertJsonCount($count, 'data.installments')->json('data.id');
    }

    /** @return list<int> */
    protected function installmentIds(int $agreement): array
    {
        return array_column($this->api('GET', "/api/spaces/{$this->pf->id}/agreements/{$agreement}")->json('data.installments'), 'id');
    }

    protected function receive(int $installment, int $account, mixed $amount, string $date, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/installments/{$installment}/receipts", [
            'account_id' => $account, 'amount' => $amount, 'received_on' => $date,
        ], ['Idempotency-Key' => $key]);
    }

    protected function assertBalance(int $account, string $expected): void
    {
        $this->api('GET', "/api/spaces/{$this->pf->id}/accounts/{$account}")->assertOk()->assertJsonPath('data.balance', $expected);
    }
}
