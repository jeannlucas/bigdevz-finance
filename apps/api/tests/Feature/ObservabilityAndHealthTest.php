<?php

namespace Tests\Feature;

use Tests\TestCase;

class ObservabilityAndHealthTest extends TestCase
{
    public function test_health_check_returns_detailed_operational_status(): void
    {
        $response = $this->getJson('/api/health');

        $response->assertOk()
            ->assertJsonPath('status', 'ok')
            ->assertJsonPath('services.database.status', 'ok')
            ->assertJsonPath('services.database.driver', 'pgsql')
            ->assertJsonPath('services.storage.status', 'ok');

        $this->assertNotNull($response->headers->get('X-Request-ID'));
    }

    public function test_every_request_receives_or_preserves_unique_request_id(): void
    {
        // 1. Gera automaticamente se não enviado
        $res1 = $this->getJson('/api/up');
        $res1->assertOk();
        $id1 = $res1->headers->get('X-Request-ID');
        $this->assertNotEmpty($id1);

        // 2. Preserva quando enviado pelo cliente
        $customId = 'req-tracing-12345';
        $res2 = $this->withHeaders(['X-Request-ID' => $customId])->getJson('/api/up');
        $res2->assertOk();
        $this->assertSame($customId, $res2->headers->get('X-Request-ID'));
    }
}
