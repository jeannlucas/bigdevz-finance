<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\Category;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RbacSecurityTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $financial;

    private User $operator;

    private User $accountant;

    private Space $pjSpace;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create(['name' => 'Admin User']);
        $this->financial = User::factory()->create(['name' => 'Financial User']);
        $this->operator = User::factory()->create(['name' => 'Operator User']);
        $this->accountant = User::factory()->create(['name' => 'Accountant User']);

        // O admin é o dono do espaço PJ
        $this->pjSpace = $this->admin->spaces()->where('kind', Space::PJ)->firstOrFail();

        // Vincular usuários com seus papéis específicos no espaço PJ
        $this->pjSpace->members()->attach([
            $this->financial->id => ['role' => Space::ROLE_FINANCIAL],
            $this->operator->id => ['role' => Space::ROLE_OPERATOR],
            $this->accountant->id => ['role' => Space::ROLE_ACCOUNTANT],
        ]);

        $this->account = $this->pjSpace->accounts()->create([
            'name' => 'Conta PJ Principal',
            'opening_balance_cents' => 500000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->category = $this->pjSpace->categories()->create([
            'name' => 'Vendas PJ',
            'type' => Category::TYPE_INCOME,
        ]);
    }

    public function test_admin_has_full_access_to_cancellations_and_adjustments(): void
    {
        Sanctum::actingAs($this->admin);

        // Criar conta a pagar
        $payable = $this->pjSpace->payables()->create([
            'kind' => 'single',
            'description' => 'Fornecedor Admin',
            'amount_cents' => 10000,
            'due_date' => '2026-05-10',
            'status' => 'pending',
        ]);

        // Admin consegue cancelar
        $response = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables/{$payable->id}/cancel", [
            'reason' => 'Cancelado pelo administrador',
        ]);
        $response->assertOk();
    }

    public function test_operator_cannot_cancel_payable(): void
    {
        Sanctum::actingAs($this->operator);

        $payable = $this->pjSpace->payables()->create([
            'kind' => 'single',
            'description' => 'Conta Operador Teste',
            'amount_cents' => 15000,
            'due_date' => '2026-05-10',
            'status' => 'pending',
        ]);

        // Operador tenta cancelar diretamente via API
        $response = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables/{$payable->id}/cancel", [
            'reason' => 'Tentativa de cancelamento por operador',
        ]);

        $response->assertStatus(403);
    }

    public function test_operator_cannot_cancel_agreement(): void
    {
        $agreement = $this->pjSpace->agreements()->create([
            'description' => 'Contrato Operador Teste',
            'total_cents' => 20000,
            'installment_count' => 1,
            'first_due_date' => '2026-05-10',
        ]);

        Sanctum::actingAs($this->operator);

        $response = $this->postJson("/api/spaces/{$this->pjSpace->id}/agreements/{$agreement->id}/cancel", [
            'reason' => 'Operador tentando cancelar contrato',
        ]);

        $response->assertStatus(403);
    }

    public function test_operator_cannot_adjust_opening_balance(): void
    {
        Sanctum::actingAs($this->operator);

        $response = $this->postJson("/api/spaces/{$this->pjSpace->id}/accounts/{$this->account->id}/opening-adjustment", [
            'new_opening_balance' => '10000.00',
            'reason' => 'Tentativa de alterar saldo inicial',
        ], ['Idempotency-Key' => 'adj-op-1']);

        $response->assertStatus(403);
    }

    public function test_accountant_cannot_move_money(): void
    {
        Sanctum::actingAs($this->accountant);

        // Contador pode listar contas e extrato
        $listResponse = $this->getJson("/api/spaces/{$this->pjSpace->id}/accounts");
        $listResponse->assertOk();

        // Mas contador é bloqueado ao tentar criar conta a pagar (movimentar dinheiro)
        $createPayable = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables", [
            'description' => 'Conta não autorizada',
            'amount' => '100.00',
            'due_date' => '2026-06-01',
        ], ['Idempotency-Key' => 'acc-pay-1']);

        $createPayable->assertStatus(403);

        // Contador é bloqueado ao tentar criar transferência
        $otherAccount = $this->pjSpace->accounts()->create([
            'name' => 'Conta Secundária',
            'opening_balance_cents' => 100000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $transferResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/transfers", [
            'source_account_id' => $this->account->id,
            'destination_account_id' => $otherAccount->id,
            'amount' => '50.00',
            'date' => '2026-05-15',
        ], ['Idempotency-Key' => 'acc-trf-1']);

        $transferResponse->assertStatus(403);
    }

    public function test_operator_cannot_reverse_payment_or_receipt(): void
    {
        Sanctum::actingAs($this->operator);

        $responseReversePayment = $this->postJson("/api/spaces/{$this->pjSpace->id}/payments/1/reversal", [
            'reason' => 'Tentativa de estorno',
        ], ['Idempotency-Key' => 'rev-pay-1']);
        $responseReversePayment->assertStatus(403);

        $responseReverseReceipt = $this->postJson("/api/spaces/{$this->pjSpace->id}/receipts/1/reversal", [
            'reason' => 'Tentativa de estorno',
        ], ['Idempotency-Key' => 'rev-rec-1']);
        $responseReverseReceipt->assertStatus(403);
    }

    public function test_operator_cannot_export_statement(): void
    {
        Sanctum::actingAs($this->operator);

        // Acesso normal à listagem funciona
        $normalResponse = $this->getJson("/api/spaces/{$this->pjSpace->id}/statement");
        $normalResponse->assertOk();

        // Tentativa de exportação é bloqueada
        $exportResponse = $this->getJson("/api/spaces/{$this->pjSpace->id}/statement?export=true");
        $exportResponse->assertStatus(403);
    }

    public function test_permissions_are_scoped_per_space_without_cross_tenant_leakage(): void
    {
        // Criar um segundo espaço PJ para outro dono
        $otherAdmin = User::factory()->create(['name' => 'Other Admin']);
        $otherSpace = $otherAdmin->spaces()->where('kind', Space::PJ)->firstOrFail();

        // O $this->admin (que é admin no pjSpace) é apenas OPERADOR no otherSpace
        $otherSpace->members()->attach([
            $this->admin->id => ['role' => Space::ROLE_OPERATOR],
        ]);

        $payableInOtherSpace = $otherSpace->payables()->create([
            'kind' => 'single',
            'description' => 'Conta do Outro Espaço',
            'amount_cents' => 30000,
            'due_date' => '2026-05-10',
            'status' => 'pending',
        ]);

        Sanctum::actingAs($this->admin);

        // No outro espaço onde ele é operador, a tentativa de cancelamento DEVE retornar 403
        $response = $this->postJson("/api/spaces/{$otherSpace->id}/payables/{$payableInOtherSpace->id}/cancel", [
            'reason' => 'Tentativa de cancelar no outro espaço',
        ]);
        $response->assertStatus(403);
    }

    public function test_only_admin_can_manage_space_members(): void
    {
        $newUser = User::factory()->create(['email' => 'novomembro@bigdevz.com']);

        // Operador tenta adicionar membro -> 403
        Sanctum::actingAs($this->operator);
        $opResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/members", [
            'email' => 'novomembro@bigdevz.com',
            'role' => Space::ROLE_FINANCIAL,
        ]);
        $opResponse->assertStatus(403);

        // Admin adiciona membro com sucesso
        Sanctum::actingAs($this->admin);
        $adminResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/members", [
            'email' => 'novomembro@bigdevz.com',
            'role' => Space::ROLE_FINANCIAL,
        ]);
        $adminResponse->assertOk();
        $this->assertDatabaseHas('space_users', [
            'space_id' => $this->pjSpace->id,
            'user_id' => $newUser->id,
            'role' => Space::ROLE_FINANCIAL,
        ]);
    }
}
