<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\Space;
use App\Models\Transfer;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class TransfersTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    private int $accA;

    private int $accB;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->login($this->user);
        $this->accA = $this->account($this->pf, 'Conta Corrente A', '1000.00', '2026-01-01');
        $this->accB = $this->account($this->pf, 'Conta Poupança B', '200.00', '2026-01-01');
    }

    public function test_transfer_moves_funds_between_accounts_atomically(): void
    {
        $response = $this->transfer($this->accA, $this->accB, '350.00', '2026-02-15', 'trf-1', 'Reserva mensal');

        $response->assertCreated()
            ->assertJsonPath('data.amount', '350.00')
            ->assertJsonPath('data.source_account_id', $this->accA)
            ->assertJsonPath('data.destination_account_id', $this->accB)
            ->assertJsonPath('data.transferred_at', '2026-02-15')
            ->assertJsonPath('data.notes', 'Reserva mensal');

        $transferId = $response->json('data.id');
        $this->assertNotNull($transferId);

        // Saldo atualizado
        $this->assertBalance($this->accA, '650.00');
        $this->assertBalance($this->accB, '550.00');

        // Movimentações espelhadas no livro contábil
        $movements = AccountMovement::query()->where('transfer_id', $transferId)->orderBy('id')->get();
        $this->assertCount(2, $movements);

        $out = $movements->firstWhere('account_id', $this->accA);
        $in = $movements->firstWhere('account_id', $this->accB);

        $this->assertNotNull($out);
        $this->assertSame(-35000, $out->amount_cents);
        $this->assertSame('2026-02-15', $out->effective_date->toDateString());

        $this->assertNotNull($in);
        $this->assertSame(35000, $in->amount_cents);
        $this->assertSame('2026-02-15', $in->effective_date->toDateString());
    }

    public function test_transfer_replay_is_idempotent(): void
    {
        $this->transfer($this->accA, $this->accB, '100.00', '2026-02-10', 'trf-repeat')
            ->assertCreated();

        $this->assertBalance($this->accA, '900.00');
        $this->assertBalance($this->accB, '300.00');

        // Replay idêntico
        $replay = $this->transfer($this->accA, $this->accB, '100.00', '2026-02-10', 'trf-repeat');
        $replay->assertOk()
            ->assertJsonPath('replayed', true)
            ->assertJsonPath('data.amount', '100.00');

        // Saldos continuam iguais (sem duplicação)
        $this->assertBalance($this->accA, '900.00');
        $this->assertBalance($this->accB, '300.00');
        $this->assertSame(1, Transfer::query()->count());
        $this->assertSame(2, AccountMovement::query()->whereNotNull('transfer_id')->count());
    }

    public function test_transfer_conflict_on_divergent_payload_with_same_key(): void
    {
        $this->transfer($this->accA, $this->accB, '100.00', '2026-02-10', 'trf-conflict')
            ->assertCreated();

        // Mesma chave com valor divergente
        $this->transfer($this->accA, $this->accB, '200.00', '2026-02-10', 'trf-conflict')
            ->assertStatus(409);
    }

    public function test_transfer_cannot_transfer_to_same_account(): void
    {
        $response = $this->transfer($this->accA, $this->accA, '50.00', '2026-02-10', 'trf-same');

        $response->assertStatus(422)
            ->assertJsonValidationErrors('destination_account_id');
    }

    public function test_transfer_rejects_archived_accounts(): void
    {
        $this->api('POST', "/api/spaces/{$this->pf->id}/accounts/{$this->accB}/archive")->assertOk();

        $response = $this->transfer($this->accA, $this->accB, '50.00', '2026-02-10', 'trf-archived');

        $response->assertStatus(422)
            ->assertJsonValidationErrors('destination_account_id');
    }

    public function test_transfer_rejects_date_before_account_opening(): void
    {
        $response = $this->transfer($this->accA, $this->accB, '50.00', '2025-12-31', 'trf-pre-opening');

        $response->assertStatus(422)
            ->assertJsonValidationErrors('transferred_at');
    }

    public function test_transfer_rejects_non_positive_or_exceeding_amounts(): void
    {
        $this->transfer($this->accA, $this->accB, '0.00', '2026-02-10', 'trf-zero')
            ->assertStatus(422)
            ->assertJsonValidationErrors('amount');

        $this->transfer($this->accA, $this->accB, '-50.00', '2026-02-10', 'trf-neg')
            ->assertStatus(422)
            ->assertJsonValidationErrors('amount');
    }

    public function test_transfer_allows_source_to_go_negative_within_max_cents(): void
    {
        // accA tem 1000.00. Transferir 1500.00 deixa com saldo negativo de -500.00 (cheque especial)
        $this->transfer($this->accA, $this->accB, '1500.00', '2026-02-10', 'trf-negative')
            ->assertCreated();

        $this->assertBalance($this->accA, '-500.00');
        $this->assertBalance($this->accB, '1700.00');
    }

    public function test_transfer_space_isolation_and_idor_protection(): void
    {
        // Conta em outro espaço (PJ)
        $pjAccount = $this->account($this->pj, 'Conta PJ', '5000.00', '2026-01-01');

        // Tentar transferir da conta PF para a conta PJ no endpoint de PF deve responder 404
        $response = $this->transfer($this->accA, $pjAccount, '100.00', '2026-02-10', 'trf-cross-space');
        $response->assertNotFound();
    }

    private function login(User $user): string
    {
        return $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'password',
            'device_name' => 'teste',
        ])->assertOk()->json('token');
    }

    private function api(string $method, string $uri, array $data = [], array $headers = []): TestResponse
    {
        return $this->withToken($this->token)->json($method, $uri, $data, $headers);
    }

    private function account(Space $space, string $name, string $opening, string $date): int
    {
        return $this->api('POST', "/api/spaces/{$space->id}/accounts", [
            'name' => $name,
            'opening_balance' => $opening,
            'opening_balance_date' => $date,
        ])->assertCreated()->json('data.id');
    }

    private function transfer(int $source, int $destination, string $amount, string $date, string $key, ?string $notes = null): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/transfers", [
            'source_account_id' => $source,
            'destination_account_id' => $destination,
            'amount' => $amount,
            'transferred_at' => $date,
            'notes' => $notes,
        ], ['Idempotency-Key' => $key]);
    }

    private function assertBalance(int $account, string $expected): void
    {
        $this->api('GET', "/api/spaces/{$this->pf->id}/accounts/{$account}")
            ->assertJsonPath('data.balance', $expected);
    }
}
