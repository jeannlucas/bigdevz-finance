<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\Space;
use App\Models\SpaceClosingLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AccountingPeriodClosingTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $operator;

    private Space $pjSpace;

    private Account $account;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create(['name' => 'Admin Test']);
        $this->operator = User::factory()->create(['name' => 'Operator Test']);

        $this->pjSpace = $this->admin->spaces()->where('kind', Space::PJ)->firstOrFail();
        $this->pjSpace->members()->attach([
            $this->operator->id => ['role' => Space::ROLE_OPERATOR],
        ]);

        $this->account = $this->pjSpace->accounts()->create([
            'name' => 'Conta Corrente PJ',
            'opening_balance_cents' => 1000000,
            'opening_balance_date' => '2026-01-01',
        ]);
    }

    public function test_admin_can_close_accounting_period_and_operator_is_forbidden(): void
    {
        // Operador tenta fechar -> 403
        Sanctum::actingAs($this->operator);
        $opResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/closing", [
            'closed_until' => '2026-10-31',
            'reason' => 'Tentativa por operador',
        ]);
        $opResponse->assertStatus(403);

        // Administrador fecha -> 200
        Sanctum::actingAs($this->admin);
        $adminResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/closing", [
            'closed_until' => '2026-10-31',
            'reason' => 'Fechamento contábil de Outubro/2026',
        ]);
        $adminResponse->assertOk()
            ->assertJson([
                'closed_until' => '2026-10-31',
            ]);

        $this->pjSpace->refresh();
        $this->assertSame('2026-10-31', $this->pjSpace->closed_until->format('Y-m-d'));

        // Verifica registro na tabela de logs de fechamento
        $this->assertDatabaseHas('space_closing_logs', [
            'space_id' => $this->pjSpace->id,
            'user_id' => $this->admin->id,
            'action' => SpaceClosingLog::ACTION_CLOSED,
            'closed_until' => '2026-10-31',
        ]);
    }

    public function test_financial_operations_in_closed_period_are_blocked(): void
    {
        // Fecha o período até 31/10/2026
        Sanctum::actingAs($this->admin);
        $this->postJson("/api/spaces/{$this->pjSpace->id}/closing", [
            'closed_until' => '2026-10-31',
            'reason' => 'Fechamento até Outubro',
        ])->assertOk();

        // 1. Tentar criar conta a pagar com vencimento no período fechado -> 422
        $payableResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables", [
            'description' => 'Boleto Passado',
            'amount' => '150.00',
            'due_date' => '2026-10-15',
        ], ['Idempotency-Key' => 'pay-closed-1']);
        $payableResponse->assertStatus(422);

        // 2. Tentar criar contrato/recebível com vencimento no período fechado -> 422
        $agreementResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/agreements", [
            'description' => 'Venda Passada',
            'total' => '500.00',
            'installment_count' => 1,
            'first_due_date' => '2026-10-10',
        ]);
        $agreementResponse->assertStatus(422);

        // 3. Tentar transferir dinheiro com data no período fechado -> 422
        $otherAccount = $this->pjSpace->accounts()->create([
            'name' => 'Poupança PJ',
            'opening_balance_cents' => 500000,
            'opening_balance_date' => '2026-01-01',
        ]);
        $transferResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/transfers", [
            'source_account_id' => $this->account->id,
            'destination_account_id' => $otherAccount->id,
            'amount' => '200.00',
            'transferred_at' => '2026-10-20',
        ], ['Idempotency-Key' => 'trf-closed-1']);
        $transferResponse->assertStatus(422);

        // 4. Operação com data APÓS o fechamento funciona perfeitamente -> 201
        $payableOkResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables", [
            'kind' => 'single',
            'description' => 'Boleto Novembro Válido',
            'amount' => '150.00',
            'due_date' => '2026-11-15',
        ], ['Idempotency-Key' => 'pay-open-1']);
        $payableOkResponse->assertStatus(201);
    }

    public function test_reopening_period_requires_admin_and_mandatory_reason(): void
    {
        Sanctum::actingAs($this->admin);
        $this->postJson("/api/spaces/{$this->pjSpace->id}/closing", [
            'closed_until' => '2026-10-31',
        ])->assertOk();

        // 1. Operador não pode reabrir -> 403
        Sanctum::actingAs($this->operator);
        $opReopen = $this->postJson("/api/spaces/{$this->pjSpace->id}/reopen", [
            'reason' => 'Tentativa de reabrir sem autorização',
        ]);
        $opReopen->assertStatus(403);

        // 2. Admin sem motivo -> 422
        Sanctum::actingAs($this->admin);
        $noReason = $this->postJson("/api/spaces/{$this->pjSpace->id}/reopen", [
            'reason' => 'abc', // menor que 5 caracteres
        ]);
        $noReason->assertStatus(422);

        // 3. Admin com motivo válido -> 200
        $validReopen = $this->postJson("/api/spaces/{$this->pjSpace->id}/reopen", [
            'reason' => 'Reabertura para ajuste fiscal aprovado pela diretoria',
            'closed_until' => '2026-09-30',
        ]);
        $validReopen->assertOk();

        $this->pjSpace->refresh();
        $this->assertSame('2026-09-30', $this->pjSpace->closed_until->format('Y-m-d'));

        // Verifica auditoria de reabertura registrada
        $this->assertDatabaseHas('space_closing_logs', [
            'space_id' => $this->pjSpace->id,
            'user_id' => $this->admin->id,
            'action' => SpaceClosingLog::ACTION_REOPENED,
            'closed_until' => '2026-09-30',
            'reason' => 'Reabertura para ajuste fiscal aprovado pela diretoria',
        ]);

        // Agora operações em Outubro passam a ser permitidas
        $payableAfterReopen = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables", [
            'kind' => 'single',
            'description' => 'Boleto Outubro Reaberto',
            'amount' => '120.00',
            'due_date' => '2026-10-15',
        ], ['Idempotency-Key' => 'pay-reopened-1']);
        $payableAfterReopen->assertStatus(201);
    }
}
