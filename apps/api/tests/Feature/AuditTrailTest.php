<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\ObligationChange;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use RuntimeException;
use Tests\TestCase;

class AuditTrailTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $operator;

    private Space $pjSpace;

    private Account $account;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create(['name' => 'Gestor Admin']);
        $this->operator = User::factory()->create(['name' => 'Operador Lucas']);

        $this->pjSpace = $this->admin->spaces()->where('kind', Space::PJ)->firstOrFail();
        $this->pjSpace->members()->attach([
            $this->operator->id => ['role' => Space::ROLE_OPERATOR],
        ]);

        $this->account = $this->pjSpace->accounts()->create([
            'name' => 'Conta Auditada',
            'opening_balance_cents' => 500000,
            'opening_balance_date' => '2026-01-01',
        ]);
    }

    public function test_audit_logs_record_complete_timeline_with_author_and_diff(): void
    {
        Sanctum::actingAs($this->admin);

        // 1. Criar conta a pagar
        $payableResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables", [
            'kind' => 'single',
            'description' => 'Serviço de Cloud',
            'amount' => '300.00',
            'due_date' => '2026-11-20',
        ], ['Idempotency-Key' => 'pay-audit-1']);
        $payableResponse->assertStatus(201);
        $payableId = $payableResponse->json('data.payables.0.id');

        // 2. Editar conta a pagar (alterando valor)
        $editResponse = $this->patchJson("/api/spaces/{$this->pjSpace->id}/payables/{$payableId}", [
            'amount' => '350.00',
            'reason' => 'Ajuste de taxa cambial',
        ]);
        $editResponse->assertOk();

        // 3. Cancelar conta a pagar
        $cancelResponse = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables/{$payableId}/cancel", [
            'reason' => 'Serviço cancelado pelo fornecedor',
        ]);
        $cancelResponse->assertOk();

        // 4. Consultar linha do tempo de auditoria via API
        $timelineResponse = $this->getJson("/api/spaces/{$this->pjSpace->id}/audit?subject=payable&subject_id={$payableId}");
        $timelineResponse->assertOk();

        $data = $timelineResponse->json('data');
        $this->assertNotEmpty($data);

        // O evento mais recente é o cancelamento (marcado como crítico)
        $latest = $data[0];
        $this->assertSame('cancel', $latest['action']);
        $this->assertTrue($latest['is_critical']);
        $this->assertSame('Serviço cancelado pelo fornecedor', $latest['reason']);
        $this->assertSame($this->admin->id, $latest['user']['id']);
        $this->assertSame('Gestor Admin', $latest['user']['name']);

        // O evento de edição possui diff estruturado
        $editEvent = collect($data)->firstWhere('action', 'edit');
        $this->assertNotNull($editEvent);
        $this->assertTrue($editEvent['is_critical']); // alteração de valor é crítica!
        $this->assertSame('Ajuste de taxa cambial', $editEvent['reason']);
        $this->assertEquals(30000, $editEvent['diff']['amount_cents']['before']);
        $this->assertEquals(35000, $editEvent['diff']['amount_cents']['after']);
    }

    public function test_audit_records_are_strictly_immutable(): void
    {
        $log = ObligationChange::create([
            'space_id' => $this->pjSpace->id,
            'user_id' => $this->admin->id,
            'subject' => 'payable',
            'subject_id' => 999,
            'action' => 'cancel',
            'before' => ['status' => 'pending'],
            'after' => ['status' => 'cancelled'],
            'reason' => 'Cancelamento imutável',
        ]);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('Registros de auditoria são estritamente imutáveis.');

        // Tentativa de update deve ser rejeitada
        $log->update(['reason' => 'Tentativa de adulteração de auditoria']);
    }

    public function test_audit_endpoint_filters_critical_operations(): void
    {
        Sanctum::actingAs($this->admin);

        // Cria log crítico (estorno)
        ObligationChange::create([
            'space_id' => $this->pjSpace->id,
            'user_id' => $this->admin->id,
            'subject' => 'payment',
            'subject_id' => 10,
            'action' => 'reverse',
            'before' => ['amount_cents' => 5000],
            'after' => ['amount_cents' => 0],
            'reason' => 'Estorno crítico',
        ]);

        // Cria log não-crítico (apenas alteração de descrição sem mexer em valores)
        ObligationChange::create([
            'space_id' => $this->pjSpace->id,
            'user_id' => $this->operator->id,
            'subject' => 'payable',
            'subject_id' => 11,
            'action' => 'edit',
            'before' => ['description' => 'Desc A', 'amount_cents' => 1000],
            'after' => ['description' => 'Desc B', 'amount_cents' => 1000],
            'reason' => 'Correção de digitação',
        ]);

        // Filtro ?critical_only=true deve retornar apenas o estorno
        $response = $this->getJson("/api/spaces/{$this->pjSpace->id}/audit?critical_only=true");
        $response->assertOk();

        $data = $response->json('data');
        $this->assertCount(1, $data);
        $this->assertSame('reverse', $data[0]['action']);
        $this->assertTrue($data[0]['is_critical']);
    }
}
