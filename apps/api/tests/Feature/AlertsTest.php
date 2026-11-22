<?php

namespace Tests\Feature;

use App\Models\Payable;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AlertsTest extends TestCase
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

    public function test_two_payables_due_on_same_date_generate_distinct_alerts_and_dismissing_one_preserves_other(): void
    {
        $yesterday = now(config('finance.timezone'))->subDays(2)->toDateString();

        $p1 = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Conta de Luz Atrasada',
            'amount_cents' => 15000,
            'paid_cents' => 0,
            'due_date' => $yesterday,
        ]);

        $p2 = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Conta de Internet Atrasada',
            'amount_cents' => 10000,
            'paid_cents' => 0,
            'due_date' => $yesterday,
        ]);

        // 1. Badge inicial deve indicar 2 alertas ativos não lidos
        $badgeResponse = $this->getJson("/api/spaces/{$this->pf->id}/alerts/badge");
        $badgeResponse->assertOk()
            ->assertJsonPath('data.unread_active_count', 2);

        // 2. Lista de alertas contém ambos
        $listResponse = $this->getJson("/api/spaces/{$this->pf->id}/alerts");
        $listResponse->assertOk();
        $this->assertCount(2, $listResponse->json('data'));

        // 3. Dispensar p1
        $dismissResponse = $this->postJson("/api/spaces/{$this->pf->id}/alerts/payable:{$p1->id}/dismiss");
        $dismissResponse->assertOk()
            ->assertJsonPath('data.is_dismissed', true);

        // 4. Badge cai para 1
        $badgeAfterDismiss = $this->getJson("/api/spaces/{$this->pf->id}/alerts/badge");
        $badgeAfterDismiss->assertOk()
            ->assertJsonPath('data.unread_active_count', 1);

        // 5. Lista ativa agora contém apenas p2
        $listAfterDismiss = $this->getJson("/api/spaces/{$this->pf->id}/alerts");
        $listAfterDismiss->assertOk();
        $items = $listAfterDismiss->json('data');
        $this->assertCount(1, $items);
        $this->assertEquals("payable:{$p2->id}", $items[0]['key']);

        // 6. A obrigação p1 continua existindo normalmente na agenda de contas a pagar
        $this->assertDatabaseHas('payables', [
            'id' => $p1->id,
            'paid_cents' => 0,
        ]);
    }

    public function test_reading_alert_updates_badge_and_keeps_alert_consultable(): void
    {
        $yesterday = now(config('finance.timezone'))->subDays(2)->toDateString();

        $p = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Conta Para Leitura',
            'amount_cents' => 8000,
            'paid_cents' => 0,
            'due_date' => $yesterday,
        ]);

        // Badge tem 1
        $this->getJson("/api/spaces/{$this->pf->id}/alerts/badge")
            ->assertOk()
            ->assertJsonPath('data.unread_active_count', 1);

        // Marca como lido
        $readResponse = $this->postJson("/api/spaces/{$this->pf->id}/alerts/payable:{$p->id}/read");
        $readResponse->assertOk()
            ->assertJsonPath('data.is_read', true);

        // Badge zera
        $this->getJson("/api/spaces/{$this->pf->id}/alerts/badge")
            ->assertOk()
            ->assertJsonPath('data.unread_active_count', 0);

        // Alerta continua consultável na lista ativa com is_read = true
        $list = $this->getJson("/api/spaces/{$this->pf->id}/alerts");
        $list->assertOk();
        $this->assertCount(1, $list->json('data'));
        $this->assertTrue($list->json('data.0.is_read'));
    }

    public function test_alert_isolation_between_spaces_and_users(): void
    {
        $yesterday = now(config('finance.timezone'))->subDays(2)->toDateString();

        $p = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Conta PF Isolada',
            'amount_cents' => 5000,
            'paid_cents' => 0,
            'due_date' => $yesterday,
        ]);

        // Dispensa no espaço PF
        $this->postJson("/api/spaces/{$this->pf->id}/alerts/payable:{$p->id}/dismiss")
            ->assertOk();

        // No espaço PJ, o badge é 0 (não vaza p de PF)
        $this->getJson("/api/spaces/{$this->pj->id}/alerts/badge")
            ->assertOk()
            ->assertJsonPath('data.unread_active_count', 0);

        // Outro usuário no mesmo espaço (se houvesse) teria seu próprio estado isolado
        [$otherUser] = $this->userWithSpaces();
        Sanctum::actingAs($otherUser);

        // Tentativa de acessar alertas do espaço PF com outro usuário deve ser bloqueada (404 / 403)
        $this->getJson("/api/spaces/{$this->pf->id}/alerts")
            ->assertNotFound();
    }
}
