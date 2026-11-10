<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\Category;
use App\Models\Payable;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CashFlowHardeningCsvInjectionTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $space;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->space = $this->user->spaces()->where('kind', Space::PJ)->firstOrFail();

        $this->account = $this->space->accounts()->create([
            'name' => 'Conta Corrente PJ',
            'type' => 'checking',
            'opening_balance_cents' => 1000000, // R$ 10.000,00
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->category = Category::create([
            'space_id' => $this->space->id,
            'name' => 'Infraestrutura',
            'type' => 'expense',
        ]);

        Sanctum::actingAs($this->user);
    }

    public function test_cash_flow_daily_aggregation_and_projections_are_exact(): void
    {
        // Cria uma conta a pagar de R$ 500,00 para 2026-06-15
        Payable::create([
            'space_id' => $this->space->id,
            'kind' => 'single',
            'description' => 'Servidor Dedicado',
            'payee' => 'Hosting Provider',
            'category_id' => $this->category->id,
            'amount_cents' => 50000,
            'due_date' => '2026-06-15',
        ]);

        $response = $this->getJson("/api/spaces/{$this->space->id}/cash-flow?days=30&view=cash&start_date=2026-06-01");

        $response->assertOk()
            ->assertJsonPath('data.initial_balance_cents', 1000000)
            ->assertJsonPath('data.summary.projected_outflow_cents', 50000);
    }

    public function test_csv_export_protects_against_formula_injection(): void
    {
        // Cria conta com saldo inicial de abertura negativo para testar o sinal de menos no CSV
        $accountNeg = $this->space->accounts()->create([
            'name' => 'Cartão PJ Rotativo',
            'type' => 'checking',
            'opening_balance_cents' => 0,
            'opening_balance_date' => '2026-01-01',
        ]);

        $response = $this->get("/api/spaces/{$this->space->id}/cash-flow?days=30&export=true");

        $response->assertOk();
        $content = $response->streamedContent();

        // O CSV não pode conter fórmulas executáveis soltas iniciadas por -, +, =, @
        // No saldo inicial, a linha do traço '-' foi sanitizada para "'-"
        $this->assertStringContainsString("'-", $content);

        // Nenhuma linha ou célula deve começar com `=cmd`, `=HYPERLINK` ou afins
        $this->assertStringNotContainsString("\n=", $content);
        $this->assertStringNotContainsString("\n@", $content);
    }

    public function test_csv_export_blocked_for_operator_role_rbac(): void
    {
        $operator = User::factory()->create();
        $this->space->members()->attach($operator->id, ['role' => 'operador']);

        Sanctum::actingAs($operator);

        $response = $this->getJson("/api/spaces/{$this->space->id}/cash-flow?days=30&export=true");
        $response->assertForbidden();
    }
}
