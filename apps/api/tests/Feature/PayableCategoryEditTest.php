<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\ObligationChange;
use App\Models\Payable;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Testes para edição de categoria em contas a pagar (AC-PAY-CAT-001..006).
 */
class PayableCategoryEditTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    private int $accountId;

    private Category $expenseCategory1;

    private Category $expenseCategory2;

    private Category $incomeCategory;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-03-15 12:00:00', 'America/Sao_Paulo'));
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->postJson('/api/auth/login', [
            'email' => $this->user->email,
            'password' => 'password',
            'device_name' => 'test-device',
        ])->json('token');

        $account = $this->pf->accounts()->create([
            'name' => 'Conta Corrente',
            'opening_balance_cents' => 100000,
            'opening_balance_date' => '2026-01-01',
        ]);
        $this->accountId = $account->id;

        $this->expenseCategory1 = $this->pf->categories()->create([
            'name' => 'Alimentação',
            'icon' => 'restaurant',
            'color' => '#FF5722',
            'type' => 'expense',
            'is_default' => false,
        ]);

        $this->expenseCategory2 = $this->pf->categories()->create([
            'name' => 'Transporte',
            'icon' => 'directions_car',
            'color' => '#2196F3',
            'type' => 'expense',
            'is_default' => false,
        ]);

        $this->incomeCategory = $this->pf->categories()->create([
            'name' => 'Salário',
            'icon' => 'work',
            'color' => '#4CAF50',
            'type' => 'income',
            'is_default' => false,
        ]);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(string $method, string $uri, array $payload = [], array $headers = []): TestResponse
    {
        return $this->json($method, $uri, $payload, ['Authorization' => "Bearer {$this->token}"] + $headers);
    }

    public function test_can_update_category_on_open_payable(): void
    {
        // 1. Cria conta a pagar avulsa com categoria 1
        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Mercado Mensal',
            'amount' => '150.00',
            'due_date' => '2026-03-25',
            'category_id' => $this->expenseCategory1->id,
        ], ['Idempotency-Key' => 'cria-mercado'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');
        $this->assertSame($this->expenseCategory1->id, Payable::findOrFail($payableId)->category_id);

        // 2. Altera a categoria para categoria 2 (AC-PAY-CAT-001)
        $updateRes = $this->api('PATCH', "/api/spaces/{$this->pf->id}/payables/{$payableId}", [
            'category_id' => $this->expenseCategory2->id,
            'reason' => 'Reclassificação para transporte',
        ])->assertOk();

        $this->assertSame($this->expenseCategory2->id, $updateRes->json('data.category.id'));
        $this->assertSame($this->expenseCategory2->id, Payable::findOrFail($payableId)->category_id);

        // 3. Auditoria registrada em obligation_changes (AC-PAY-CAT-004)
        $change = ObligationChange::where('subject', 'payable')
            ->where('subject_id', $payableId)
            ->where('action', 'edit')
            ->latest('id')
            ->first();

        $this->assertNotNull($change);
        $this->assertSame($this->expenseCategory1->id, $change->before['category_id']);
        $this->assertSame($this->expenseCategory2->id, $change->after['category_id']);
    }

    public function test_can_remove_category_from_payable(): void
    {
        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Gasto Geral',
            'amount' => '50.00',
            'due_date' => '2026-03-25',
            'category_id' => $this->expenseCategory1->id,
        ], ['Idempotency-Key' => 'cria-geral'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');

        // Remove categoria atribuindo null
        $this->api('PATCH', "/api/spaces/{$this->pf->id}/payables/{$payableId}", [
            'category_id' => null,
        ])->assertOk()->assertJsonPath('data.category', null);

        $this->assertNull(Payable::findOrFail($payableId)->category_id);
    }

    public function test_rejects_category_from_another_space_with_404(): void
    {
        // Categoria criada no espaço PJ
        $pjCategory = $this->pj->categories()->create([
            'name' => 'Insumos PJ',
            'icon' => 'inventory',
            'color' => '#9C27B0',
            'type' => 'expense',
            'is_default' => false,
        ]);

        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Despesa PF',
            'amount' => '80.00',
            'due_date' => '2026-03-25',
        ], ['Idempotency-Key' => 'cria-pf-idor'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');

        // Tenta vincular categoria do espaço PJ no espaço PF (AC-PAY-CAT-003)
        $this->api('PATCH', "/api/spaces/{$this->pf->id}/payables/{$payableId}", [
            'category_id' => $pjCategory->id,
        ])->assertNotFound();
    }

    public function test_rejects_income_category_for_payable(): void
    {
        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Despesa PF',
            'amount' => '80.00',
            'due_date' => '2026-03-25',
        ], ['Idempotency-Key' => 'cria-pf-type'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');

        // Tenta vincular categoria de receita (type = income) em conta a pagar (AC-PAY-CAT-002)
        $this->api('PATCH', "/api/spaces/{$this->pf->id}/payables/{$payableId}", [
            'category_id' => $this->incomeCategory->id,
        ])->assertNotFound();
    }

    public function test_can_update_category_on_liquidated_payable_without_affecting_balance(): void
    {
        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Conta de Energia',
            'amount' => '120.00',
            'due_date' => '2026-03-20',
            'category_id' => $this->expenseCategory1->id,
        ], ['Idempotency-Key' => 'cria-energia'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');

        // Paga a conta integralmente
        $this->api('POST', "/api/spaces/{$this->pf->id}/payables/{$payableId}/payments", [
            'account_id' => $this->accountId,
            'amount' => '120.00',
            'paid_on' => '2026-03-10',
        ], ['Idempotency-Key' => 'paga-energia'])->assertCreated();

        $accountBefore = $this->pf->accounts()->findOrFail($this->accountId);
        $movementsCountBefore = $accountBefore->movements()->count();
        $balanceBefore = $accountBefore->balanceCents();

        // Altera a categoria da conta JÁ LIQUIDADA (AC-PAY-CAT-005)
        $this->api('PATCH', "/api/spaces/{$this->pf->id}/payables/{$payableId}", [
            'category_id' => $this->expenseCategory2->id,
            'reason' => 'Ajuste contábil de classificação',
        ])->assertOk()->assertJsonPath('data.category.id', $this->expenseCategory2->id);

        $payable = Payable::findOrFail($payableId);
        $this->assertSame($this->expenseCategory2->id, $payable->category_id);
        $this->assertSame('paid', $payable->status());

        // Movimentações contábeis permanecem intocadas (imutabilidade contábil)
        $accountAfter = $this->pf->accounts()->findOrFail($this->accountId);
        $this->assertSame($movementsCountBefore, $accountAfter->movements()->count());
        $this->assertSame($balanceBefore, $accountAfter->balanceCents());
    }
}
