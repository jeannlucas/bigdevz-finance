<?php

namespace Tests\Feature;

use App\Actions\Receivables\CreateAgreement;
use App\Models\Account;
use App\Models\Category;
use App\Models\Space;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CashFlowPlanningTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $operator;

    private Space $space;

    private Account $account;

    private Category $categoryIncome;

    private Category $categoryExpense;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create(['name' => 'Admin Planejamento']);
        $this->operator = User::factory()->create(['name' => 'Operador Planejamento']);

        $this->space = $this->admin->spaces()->where('kind', Space::PJ)->firstOrFail();
        $this->space->members()->attach([
            $this->operator->id => ['role' => Space::ROLE_OPERATOR],
        ]);

        $this->account = $this->space->accounts()->create([
            'name' => 'Conta Planejamento',
            'opening_balance_cents' => 500000, // R$ 5.000,00
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->categoryIncome = $this->space->categories()->create([
            'name' => 'Vendas',
            'type' => Category::TYPE_INCOME,
            'color' => '#10B981',
            'icon' => 'tag',
        ]);

        $this->categoryExpense = $this->space->categories()->create([
            'name' => 'Fornecedores',
            'type' => Category::TYPE_EXPENSE,
            'color' => '#EF4444',
            'icon' => 'tag',
        ]);
    }

    public function test_cash_flow_planning_calculates_daily_realized_and_projected(): void
    {
        Sanctum::actingAs($this->admin);

        $today = Carbon::today()->format('Y-m-d');
        $in5Days = Carbon::today()->addDays(5)->format('Y-m-d');
        $in15Days = Carbon::today()->addDays(15)->format('Y-m-d');

        // 1. Criar conta a pagar com vencimento em 5 dias (prevista: R$ 1.000,00)
        $this->postJson("/api/spaces/{$this->space->id}/payables", [
            'kind' => 'single',
            'description' => 'Servidor Dedicado',
            'amount' => '1000.00',
            'due_date' => $in5Days,
            'category_id' => $this->categoryExpense->id,
        ], ['Idempotency-Key' => 'cf-payable-1'])->assertCreated();

        // 2. Criar conta a receber com vencimento em 15 dias (prevista: R$ 3.000,00)
        app(CreateAgreement::class)->handle(
            $this->space,
            'Projeto Web',
            '3000.00',
            1,
            $in15Days,
            $this->categoryIncome->id,
        );

        // 3. Consultar planejamento para 30 dias
        $res = $this->getJson("/api/spaces/{$this->space->id}/cash-flow?days=30&view=cash");
        $res->assertOk();

        $data = $res->json('data');
        $this->assertEquals(500000, $data['initial_balance_cents']);
        $this->assertEquals(30, $data['period_days']);
        $this->assertEquals(300000, $data['summary']['projected_inflow_cents']);
        $this->assertEquals(100000, $data['summary']['projected_outflow_cents']);
        $this->assertNotEmpty($data['daily']);
        $this->assertCount(30, $data['daily']);

        // No dia 5, saída projetada deve ser 100000 centavos
        $day5 = collect($data['daily'])->firstWhere('date', $in5Days);
        $this->assertNotNull($day5);
        $this->assertEquals(100000, $day5['projected_outflow_cents']);

        // No dia 15, entrada projetada deve ser 300000 centavos
        $day15 = collect($data['daily'])->firstWhere('date', $in15Days);
        $this->assertNotNull($day15);
        $this->assertEquals(300000, $day15['projected_inflow_cents']);
    }

    public function test_cash_flow_filters_by_category_and_account(): void
    {
        Sanctum::actingAs($this->admin);

        $in3Days = Carbon::today()->addDays(3)->format('Y-m-d');

        $this->postJson("/api/spaces/{$this->space->id}/payables", [
            'kind' => 'single',
            'description' => 'Matéria Prima',
            'amount' => '400.00',
            'due_date' => $in3Days,
            'category_id' => $this->categoryExpense->id,
        ], ['Idempotency-Key' => 'cf-payable-cat'])->assertCreated();

        // Filtro por categoria existente
        $res = $this->getJson("/api/spaces/{$this->space->id}/cash-flow?days=30&category_id={$this->categoryExpense->id}");
        $res->assertOk();
        $this->assertEquals(40000, $res->json('data.summary.projected_outflow_cents'));

        // Filtro por categoria não correspondente
        $resOther = $this->getJson("/api/spaces/{$this->space->id}/cash-flow?days=30&category_id={$this->categoryIncome->id}");
        $resOther->assertOk();
        $this->assertEquals(0, $resOther->json('data.summary.projected_outflow_cents'));
    }

    public function test_cash_flow_export_security_and_rbac(): void
    {
        // Administrador pode exportar
        Sanctum::actingAs($this->admin);
        $exportAdmin = $this->getJson("/api/spaces/{$this->space->id}/cash-flow?days=30&export=true");
        $exportAdmin->assertOk();
        $exportAdmin->assertHeader('content-type', 'text/csv; charset=UTF-8');

        // Operador é bloqueado na exportação (HTTP 403)
        Sanctum::actingAs($this->operator);
        $exportOp = $this->getJson("/api/spaces/{$this->space->id}/cash-flow?days=30&export=true");
        $exportOp->assertForbidden();
    }
}
