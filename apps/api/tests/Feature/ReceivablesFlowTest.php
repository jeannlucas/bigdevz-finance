<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\User;
use Carbon\Carbon;
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

    /**
     * Resposta perdida após a gravação: o app resolve reenviando a mesma chave
     * e o mesmo conteúdo. Parcela de R$ 2.000,00 e R$ 500,00, para que um
     * segundo recebimento coubesse e o limite não mascarasse a duplicação.
     */
    public function test_lost_response_resend_with_same_key_records_partial_once(): void
    {
        $account = $this->createAccount($this->pf, '1000.00', '2026-01-01');
        $ids = $this->installmentIds($this->createAgreement($this->pf, '24000.00', 12, '2026-02-10'));

        $original = $this->receive($ids[0], $account, '500.00', '2026-02-10', 'perdida')->assertCreated();
        // A resposta acima "se perdeu"; a verificação repete a mesma tentativa.
        $this->receive($ids[0], $account, '500.00', '2026-02-10', 'perdida')
            ->assertOk()
            ->assertJsonPath('data.replayed', true)
            ->assertJsonPath('data.receipt.id', $original->json('data.receipt.id'))
            ->assertJsonPath('data.installment.remaining', '1500.00')
            ->assertJsonPath('data.account.balance', '1500.00');

        $this->assertSame(1, Receipt::query()->where('installment_id', $ids[0])->count());
        $this->assertSame(1, AccountMovement::query()->where('account_id', $account)->count());
        $this->assertBalance($account, '1500.00');

        // Uma chave nova com outros dados SERIA aceita: é isso que o app impede
        // enquanto a tentativa original não for resolvida.
        $this->receive($ids[0], $account, '400.00', '2026-02-10', 'outra')->assertCreated();
        $this->assertSame(2, Receipt::query()->where('installment_id', $ids[0])->count());
    }

    /** 422 com a mesma chave: nada gravado, nem no reenvio. */
    public function test_rejected_attempt_records_nothing_and_resend_is_rejected_again(): void
    {
        $account = $this->createAccount($this->pf, '1000.00', '2026-01-01');
        $ids = $this->installmentIds($this->createAgreement($this->pf, '24000.00', 12, '2026-02-10'));

        foreach (range(1, 2) as $_) {
            $this->receive($ids[0], $account, '2000.01', '2026-02-10', 'recusada')
                ->assertStatus(422)
                ->assertJsonValidationErrors('amount');
        }
        $this->assertSame(0, Receipt::query()->where('idempotency_key', 'recusada')->count());
        $this->assertSame(0, AccountMovement::query()->where('account_id', $account)->count());
        $this->assertBalance($account, '1000.00');
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
            // Chave distinta por conteúdo: '100' e 100 são pedidos diferentes.
            $this->receive($ids[0], $account, $amount, '2026-02-10', 'k-'.md5(var_export($amount, true)))
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

    public function test_agreements_status_filters(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-03-15 12:00:00', 'America/Sao_Paulo'));
        try {
            $account = $this->createAccount($this->pf, '1000.00', '2026-01-01');

            // 1. Acordo A: Vencido (vencimento 2026-03-01)
            $agrA = $this->createAgreement($this->pf, '100.00', 1, '2026-03-01');

            // 2. Acordo B: Vence Hoje (vencimento 2026-03-15)
            $agrB = $this->createAgreement($this->pf, '200.00', 1, '2026-03-15');

            // 3. Acordo C: Vence em 10 dias (vencimento 2026-03-25, dentro dos 30 dias)
            $agrC = $this->createAgreement($this->pf, '300.00', 1, '2026-03-25');

            // 4. Acordo D: Quitado
            $agrD = $this->createAgreement($this->pf, '400.00', 1, '2026-03-01');
            $instD = $this->installmentIds($agrD)[0];
            $this->receive($instD, $account, '400.00', '2026-03-01', 'rec-d')->assertCreated();

            // 5. Acordo E: Misto (parcela 1 vencida em 2026-03-01, parcela 2 em 2026-03-25 próxima 30 dias)
            $agrE = $this->createAgreement($this->pf, '500.00', 2, '2026-03-01');

            $base = "/api/spaces/{$this->pf->id}/agreements";

            // Default / open: A, B, C, E (todos com saldo em aberto)
            $open = $this->api('GET', "{$base}?status=open")->assertOk()->json('data');
            $this->assertEqualsCanonicalizing([$agrA, $agrB, $agrC, $agrE], array_column($open, 'id'));

            // overdue: A e E
            $overdue = $this->api('GET', "{$base}?status=overdue")->assertOk()->json('data');
            $this->assertEqualsCanonicalizing([$agrA, $agrE], array_column($overdue, 'id'));

            // today: B
            $today = $this->api('GET', "{$base}?status=today")->assertOk()->json('data');
            $this->assertEqualsCanonicalizing([$agrB], array_column($today, 'id'));

            // next_30_days: C e E
            $next30 = $this->api('GET', "{$base}?status=next_30_days")->assertOk()->json('data');
            $this->assertEqualsCanonicalizing([$agrC, $agrE], array_column($next30, 'id'));

            // paid: D
            $paid = $this->api('GET', "{$base}?status=paid")->assertOk()->json('data');
            $this->assertEqualsCanonicalizing([$agrD], array_column($paid, 'id'));

            // all: A, B, C, D, E
            $allRes = $this->api('GET', "{$base}?status=all")->assertOk();
            $all = $allRes->json('data');
            $this->assertEqualsCanonicalizing([$agrA, $agrB, $agrC, $agrD, $agrE], array_column($all, 'id'));
            $allRes->assertJsonPath('meta.total_count', 5);
        } finally {
            Carbon::setTestNow();
        }
    }
}
