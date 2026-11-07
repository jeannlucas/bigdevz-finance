<?php

namespace Tests\Feature;

use Tests\TestCase;

class CorsPreflightTest extends TestCase
{
    public function test_api_options_preflight_returns_cors_headers(): void
    {
        $response = $this->withHeaders([
            'Origin' => 'http://localhost:3000',
            'Access-Control-Request-Method' => 'POST',
            'Access-Control-Request-Headers' => 'Content-Type, Authorization, Idempotency-Key',
        ])->options('/api/auth/login');

        $response->assertStatus(204);
        $response->assertHeader('Access-Control-Allow-Origin', '*');
        $response->assertHeader('Access-Control-Allow-Methods');
        $response->assertHeader('Access-Control-Allow-Headers');
    }

    public function test_api_get_request_returns_cors_headers_with_origin(): void
    {
        $response = $this->withHeaders([
            'Origin' => 'http://localhost:8080',
        ])->getJson('/api/auth/user');

        $response->assertHeader('Access-Control-Allow-Origin', '*');
    }
}
