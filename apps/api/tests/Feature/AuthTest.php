<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use DatabaseTransactions;

    public function test_me_returns_authenticated_user_profile(): void
    {
        [$user] = $this->userWithSpaces();
        Sanctum::actingAs($user);

        $response = $this->getJson('/api/me');

        $response->assertOk()
            ->assertJson([
                'data' => [
                    'id' => $user->id,
                    'name' => $user->name,
                    'email' => $user->email,
                ],
            ]);
    }

    public function test_patch_me_updates_user_name_successfully(): void
    {
        [$user] = $this->userWithSpaces();
        Sanctum::actingAs($user);

        $response = $this->patchJson('/api/me', [
            'name' => 'Jeann Lucas Atualizado',
        ]);

        $response->assertOk()
            ->assertJson([
                'data' => [
                    'id' => $user->id,
                    'name' => 'Jeann Lucas Atualizado',
                    'email' => $user->email,
                ],
            ]);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Jeann Lucas Atualizado',
        ]);
    }

    public function test_patch_me_validates_name_field(): void
    {
        [$user] = $this->userWithSpaces();
        Sanctum::actingAs($user);

        $this->patchJson('/api/me', ['name' => ''])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['name']);

        $this->patchJson('/api/me', ['name' => 'A'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['name']);
    }

    public function test_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/me')->assertUnauthorized();
        $this->patchJson('/api/me', ['name' => 'Novo Nome'])->assertUnauthorized();
    }

    public function test_login_authenticates_with_case_insensitive_email(): void
    {
        [$user] = $this->userWithSpaces();

        // Login com email original
        $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'password',
            'device_name' => 'test-device',
        ])->assertOk()->assertJsonStructure(['token', 'user']);

        // Login com email em maiúsculas (resiliência contra teclados móveis e autofill)
        $this->postJson('/api/auth/login', [
            'email' => strtoupper($user->email),
            'password' => 'password',
            'device_name' => 'test-device',
        ])->assertOk()->assertJsonStructure(['token', 'user']);
    }

    public function test_login_rejects_invalid_credentials(): void
    {
        [$user] = $this->userWithSpaces();

        $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'senha-incorreta',
            'device_name' => 'test-device',
        ])->assertUnprocessable()->assertJsonValidationErrors(['email']);
    }
}
