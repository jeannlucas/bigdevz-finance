<?php

namespace Tests\Feature;

use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UserCreateCommandTest extends TestCase
{
    use RefreshDatabase;

    public function test_creates_user_with_pf_and_pj_spaces(): void
    {
        $this->artisan('user:create test@example.com --name="Usuário Teste" --password=segredo-forte')
            ->expectsOutputToContain('Usuário test@example.com criado')
            ->expectsOutput('Senha definida.')
            ->assertExitCode(0);

        $user = User::where('email', 'test@example.com')->first();
        $this->assertNotNull($user);
        $this->assertSame('Usuário Teste', $user->name);
        $this->assertTrue(Hash::check('segredo-forte', $user->password));

        // Spaces criados automaticamente pelo boot do modelo
        $this->assertTrue($user->spaces()->where('kind', Space::PF)->exists());
        $this->assertTrue($user->spaces()->where('kind', Space::PJ)->exists());
    }

    public function test_normalizes_email_and_updates_existing_user(): void
    {
        $user = User::factory()->create([
            'email' => 'developer@example.com',
            'name' => 'Antigo Nome',
        ]);

        $this->artisan('user:create DEVELOPER@EXAMPLE.COM --name="Novo Nome" --password=nova-senha')
            ->expectsOutputToContain('Usuário developer@example.com pronto')
            ->assertExitCode(0);

        $user->refresh();
        $this->assertSame('Novo Nome', $user->name);
        $this->assertTrue(Hash::check('nova-senha', $user->password));
    }

    public function test_generates_random_password_when_not_provided(): void
    {
        $this->artisan('user:create random@example.com')
            ->expectsOutputToContain('Senha gerada:')
            ->assertExitCode(0);

        $user = User::where('email', 'random@example.com')->first();
        $this->assertNotNull($user);
        $this->assertNotEmpty($user->password);
    }
}
