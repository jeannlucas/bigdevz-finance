<?php

namespace Tests\Feature;

use App\Actions\Payables\GenerateObligations;
use App\Models\AccountMovement;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SpaceSummaryTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        Sanctum::actingAs($this->user);
    }

    /** T-01: Soma superior a MAX_CENTS totalizando R$ 1,2 trilhão exato sem float ('1200000000000.00'). */
    public function test_t01_summary_calculates_balance_exceeding_individual_limit_without_float(): void
    {
        // R$ 600.000.000.000,00 = 60.000.000.000.000 centavos cada (abaixo de MAX_CENTS = 99.999.999.999.999)
        $this->pf->accounts()->create([
            'name' => 'Holding A',
            'opening_balance_cents' => 60000000000000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->pf->accounts()->create([
            'name' => 'Holding B',
            'opening_balance_cents' => 60000000000000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->getJson("/api/spaces/{$this->pf->id}/summary")
            ->assertOk()
            ->assertJsonPath('data.balance', '1200000000000.00')
            ->assertJsonPath('data.accounts_count', 2)
            ->assertJsonPath('data.active_accounts_count', 2);
    }

    /** T-02: Soma monetária regular dentro de MAX_CENTS. */
    public function test_t02_summary_calculates_balance_within_individual_limit(): void
    {
        $this->postJson("/api/spaces/{$this->pf->id}/accounts", [
            'name' => 'Conta 1', 'opening_balance' => '1000.00', 'opening_balance_date' => '2026-01-01',
        ])->assertCreated();

        $this->postJson("/api/spaces/{$this->pf->id}/accounts", [
            'name' => 'Conta 2', 'opening_balance' => '500.00', 'opening_balance_date' => '2026-01-01',
        ])->assertCreated();

        $this->getJson("/api/spaces/{$this->pf->id}/summary")
            ->assertOk()
            ->assertJsonPath('data.balance', '1500.00')
            ->assertJsonPath('data.accounts_count', 2)
            ->assertJsonPath('data.active_accounts_count', 2);
    }

    /** T-03: Agregado negativo válido (após despesas/pagamentos superiores ao saldo de abertura). */
    public function test_t03_summary_handles_valid_negative_aggregate_balance(): void
    {
        $account = $this->pf->accounts()->create([
            'name' => 'Conta Corrente',
            'opening_balance_cents' => 5000, // R$ 50,00
            'opening_balance_date' => '2026-01-01',
        ]);

        $payable = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => 'single',
            'description' => 'Serviço',
            'amount_cents' => 25000, // R$ 250,00
            'due_date' => '2026-01-10',
        ]);

        $payment = Payment::create([
            'space_id' => $this->pf->id,
            'payable_id' => $payable->id,
            'account_id' => $account->id,
            'user_id' => $this->user->id,
            'amount_cents' => 25000,
            'paid_on' => '2026-01-10',
        ]);

        AccountMovement::create([
            'account_id' => $account->id,
            'payment_id' => $payment->id,
            'amount_cents' => -25000,
            'effective_date' => '2026-01-10',
        ]);

        // Saldo da conta: 50.00 - 250.00 = -200.00
        $this->getJson("/api/spaces/{$this->pf->id}/summary")
            ->assertOk()
            ->assertJsonPath('data.balance', '-200.00');
    }

    /** T-04: Multi-tenant: isolamento de Space de outro usuário (404) e segregação PF/PJ do mesmo usuário. */
    public function test_t04_summary_enforces_multi_tenant_isolation_across_users_and_spaces(): void
    {
        // 1. Outro usuário recebe 404
        $otherUser = User::factory()->create();
        $otherSpace = $otherUser->spaces()->where('kind', 'PF')->firstOrFail();

        $this->getJson("/api/spaces/{$otherSpace->id}/summary")
            ->assertNotFound()
            ->assertJsonMissingPath('data');

        // 2. Segregação PF vs PJ do mesmo usuário
        $this->pf->accounts()->create([
            'name' => 'Carteira PF',
            'opening_balance_cents' => 100000, // R$ 1.000,00
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->pj->accounts()->create([
            'name' => 'Conta PJ',
            'opening_balance_cents' => 50000, // R$ 500,00
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->getJson("/api/spaces/{$this->pf->id}/summary")
            ->assertOk()
            ->assertJsonPath('data.balance', '1000.00')
            ->assertJsonPath('data.accounts_count', 1);

        $this->getJson("/api/spaces/{$this->pj->id}/summary")
            ->assertOk()
            ->assertJsonPath('data.balance', '500.00')
            ->assertJsonPath('data.accounts_count', 1);
    }

    /** T-05: Espaço recém-criado sem contas retorna zero em balance e accounts_count. */
    public function test_t05_summary_returns_zero_balance_for_space_without_accounts(): void
    {
        $this->getJson("/api/spaces/{$this->pf->id}/summary")
            ->assertOk()
            ->assertJsonPath('data.balance', '0.00')
            ->assertJsonPath('data.accounts_count', 0)
            ->assertJsonPath('data.active_accounts_count', 0);
    }

    /** T-06: Duas contas individuais cada uma com MAX_CENTS somando exatamente 2 x MAX_CENTS ('1999999999999.98'). */
    public function test_t06_summary_calculates_sum_of_two_max_cents_accounts_exactly(): void
    {
        $maxCents = 99999999999999; // R$ 999.999.999.999,99

        $this->pf->accounts()->create([
            'name' => 'Conta Teto 1',
            'opening_balance_cents' => $maxCents,
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->pf->accounts()->create([
            'name' => 'Conta Teto 2',
            'opening_balance_cents' => $maxCents,
            'opening_balance_date' => '2026-01-01',
        ]);

        // 999999999999.99 + 999999999999.99 = 1999999999999.98
        $this->getJson("/api/spaces/{$this->pf->id}/summary")
            ->assertOk()
            ->assertJsonPath('data.balance', '1999999999999.98')
            ->assertJsonPath('data.accounts_count', 2)
            ->assertJsonPath('data.active_accounts_count', 2);
    }

    /** T-07: Resposta JSON preserva strings decimais canônicas com ponto e exatamente duas casas decimais em todos os totalizadores com valores não-zero e assert exato. */
    public function test_t07_summary_preserves_canonical_decimal_strings_across_all_financial_fields(): void
    {
        $today = GenerateObligations::today();

        $account = $this->pf->accounts()->create([
            'name' => 'Conta Geral',
            'opening_balance_cents' => 100000, // R$ 1.000,00
            'opening_balance_date' => '2026-01-01',
        ]);

        // Acordo com parcela a receber e recebimento parcial
        $agrRes = $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Serviço prestado',
            'total' => '500.00',
            'installment_count' => 1,
            'first_due_date' => Carbon::parse($today)->addDays(40)->toDateString(),
        ])->assertCreated();
        $agrId = $agrRes->json('data.id');
        $instId = $this->getJson("/api/spaces/{$this->pf->id}/agreements/{$agrId}")->json('data.installments.0.id');

        $this->postJson("/api/spaces/{$this->pf->id}/installments/{$instId}/receipts", [
            'account_id' => $account->id,
            'amount' => '150.00',
            'received_on' => $today,
        ], ['Idempotency-Key' => 'rec-summary-t07'])->assertCreated();

        // 1. Obrigação vencida no passado (overdue) sem pagamento
        $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Conta Vencida',
            'amount' => '200.00',
            'due_date' => Carbon::parse($today)->subDays(5)->toDateString(),
        ], ['Idempotency-Key' => 'pay-overdue-t07'])->assertCreated();

        // 2. Obrigação a vencer nos próximos 30 dias com pagamento parcial
        $payRes = $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Aluguel Próximo',
            'amount' => '800.00',
            'due_date' => Carbon::parse($today)->addDays(10)->toDateString(),
        ], ['Idempotency-Key' => 'pay-upcoming-t07'])->assertCreated();
        $payableId = $payRes->json('data.payables.0.id');

        $this->postJson("/api/spaces/{$this->pf->id}/payables/{$payableId}/payments", [
            'account_id' => $account->id,
            'amount' => '300.00',
            'paid_on' => $today,
        ], ['Idempotency-Key' => 'payment-t07'])->assertCreated();

        $response = $this->getJson("/api/spaces/{$this->pf->id}/summary")->assertOk();
        $data = $response->json('data');

        $canonicalRegex = '/^(-?)(0|[1-9][0-9]*)\.([0-9]{2})$/';

        // 1. Verificação de formato decimal canônico em todos os campos financeiros
        $this->assertMatchesRegularExpression($canonicalRegex, $data['balance']);
        $this->assertMatchesRegularExpression($canonicalRegex, $data['received_total']);
        $this->assertMatchesRegularExpression($canonicalRegex, $data['receivable_remaining']);
        $this->assertMatchesRegularExpression($canonicalRegex, $data['payables']['open_total']);
        $this->assertMatchesRegularExpression($canonicalRegex, $data['payables']['overdue_total']);
        $this->assertMatchesRegularExpression($canonicalRegex, $data['payables']['due_next_30_days_total']);
        $this->assertMatchesRegularExpression($canonicalRegex, $data['payables']['paid_total']);

        // 2. Verificação de exatidão matemática dos totalizadores (todos com valores não-zero)
        // Saldo = 1000.00 + 150.00 (recebimento) - 300.00 (pagamento) = 850.00
        $this->assertSame('850.00', $data['balance']);
        $this->assertSame('150.00', $data['received_total']);
        $this->assertSame('350.00', $data['receivable_remaining']);
        // Open total = 200.00 (vencida) + 500.00 (800 - 300) = 700.00
        $this->assertSame('700.00', $data['payables']['open_total']);
        $this->assertSame('200.00', $data['payables']['overdue_total']);
        $this->assertSame('500.00', $data['payables']['due_next_30_days_total']);
        $this->assertSame('300.00', $data['payables']['paid_total']);
    }
}
