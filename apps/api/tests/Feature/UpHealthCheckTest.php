<?php

namespace Tests\Feature;

use Tests\TestCase;

class UpHealthCheckTest extends TestCase
{
    public function test_up_health_check_returns_ok_status(): void
    {
        $response = $this->getJson('/api/up');

        $response->assertOk()
            ->assertExactJson(['status' => 'ok']);
    }
}
