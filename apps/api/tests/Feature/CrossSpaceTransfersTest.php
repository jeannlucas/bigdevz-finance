<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\Space;
use App\Models\TransferReversal;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class CrossSpaceTransfersTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    private int $accPf;

    private int $accPj;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->login($this->user);
        $this->accPf = $this->account($this->pf, 'Nubank PF', '1000.00', '2026-01-01');
        $this->accPj = $this->account($this->pj, 'Itaú PJ', '10000.00', '2026-01-01');
    }

    public function test_transfer_from_pj_to_pf_moves_funds_and_updates_balances_and_statements(): void
    {
        $response = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", [
            'source_account_id' => $this->accPj,
            'destination_space_id' => $this->pf->id,
            'destination_account_id' => $this->accPf,
            'amount' => '2500.00',
            'transferred_at' => '2026-02-15',
            'notes' => 'Reembolso despesa de TI paga na PF',
        ], ['Idempotency-Key' => 'trf-pj-pf-1']);

        $response->assertCreated()
            ->assertJsonPath('data.amount', '2500.00')
            ->assertJsonPath('data.source_account_id', $this->accPj)
            ->assertJsonPath('data.destination_account_id', $this->accPf)
            ->assertJsonPath('data.space_id', $this->pj->id)
            ->assertJsonPath('data.destination_space_id', $this->pf->id)
            ->assertJsonPath('data.is_cross_space', true)
            ->assertJsonPath('data.notes', 'Reembolso despesa de TI paga na PF');

        $transferId = $response->json('data.id');
        $this->assertNotNull($transferId);

        // Saldos atualizados exatamente
        $this->assertBalance($this->pj, $this->accPj, '7500.00');
        $this->assertBalance($this->pf, $this->accPf, '3500.00');

        // Movimentações contábeis vinculadas
        $movements = AccountMovement::query()->where('transfer_id', $transferId)->get();
        $this->assertCount(2, $movements);

        $out = $movements->firstWhere('account_id', $this->accPj);
        $in = $movements->firstWhere('account_id', $this->accPf);

        $this->assertNotNull($out);
        $this->assertSame(-250000, $out->amount_cents);

        $this->assertNotNull($in);
        $this->assertSame(250000, $in->amount_cents);

        // Extrato PJ: saída com identificação da conta e espaço de destino
        $statementPj = $this->api('GET', "/api/spaces/{$this->pj->id}/statement")->assertOk()->json('data');
        $movementPj = collect($statementPj)->firstWhere('raw_amount_cents', -250000);
        $this->assertNotNull($movementPj);
        $this->assertStringContainsStringIgnoringCase('Nubank PF', $movementPj['description']);
        $this->assertStringContainsString($this->pf->name, $movementPj['description']);

        // Extrato PF: entrada com identificação da conta e espaço de origem
        $statementPf = $this->api('GET', "/api/spaces/{$this->pf->id}/statement")->assertOk()->json('data');
        $movementPf = collect($statementPf)->firstWhere('raw_amount_cents', 250000);
        $this->assertNotNull($movementPf);
        $this->assertStringContainsStringIgnoringCase('Itaú PJ', $movementPf['description']);
        $this->assertStringContainsString($this->pj->name, $movementPf['description']);
    }

    public function test_transfer_from_pf_to_pj_moves_funds_inversely(): void
    {
        $response = $this->api('POST', "/api/spaces/{$this->pf->id}/transfers", [
            'source_account_id' => $this->accPf,
            'destination_space_id' => $this->pj->id,
            'destination_account_id' => $this->accPj,
            'amount' => '300.00',
            'transferred_at' => '2026-02-16',
            'notes' => 'Aporte inicial do sócio',
        ], ['Idempotency-Key' => 'trf-pf-pj-1']);

        $response->assertCreated()
            ->assertJsonPath('data.amount', '300.00')
            ->assertJsonPath('data.source_account_id', $this->accPf)
            ->assertJsonPath('data.destination_account_id', $this->accPj)
            ->assertJsonPath('data.space_id', $this->pf->id)
            ->assertJsonPath('data.destination_space_id', $this->pj->id)
            ->assertJsonPath('data.is_cross_space', true);

        $this->assertBalance($this->pf, $this->accPf, '700.00');
        $this->assertBalance($this->pj, $this->accPj, '10300.00');
    }

    public function test_transfer_requires_access_to_both_spaces_and_protects_against_idor(): void
    {
        // Outro usuário com outro espaço
        [$otherUser, $otherPf] = $this->userWithSpaces();
        $otherAcc = $otherPf->accounts()->create([
            'name' => 'CONTA ALHEIA',
            'opening_balance_cents' => 50000,
            'opening_balance_date' => '2026-01-01',
        ])->id;

        // Tentar transferir para espaço alheio responde 404
        $res1 = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", [
            'source_account_id' => $this->accPj,
            'destination_space_id' => $otherPf->id,
            'destination_account_id' => $otherAcc,
            'amount' => '100.00',
            'transferred_at' => '2026-02-15',
        ], ['Idempotency-Key' => 'trf-idor-1']);
        $res1->assertNotFound();

        // Tentar transferir para conta alheia usando o espaço do próprio usuário responde 404
        $res2 = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", [
            'source_account_id' => $this->accPj,
            'destination_space_id' => $this->pf->id,
            'destination_account_id' => $otherAcc,
            'amount' => '100.00',
            'transferred_at' => '2026-02-15',
        ], ['Idempotency-Key' => 'trf-idor-2']);
        $res2->assertNotFound();
    }

    public function test_rbac_rejects_transfer_if_user_is_accountant_in_either_space(): void
    {
        // Torna o usuário contador no espaço PJ
        $this->pj->members()->updateExistingPivot($this->user->id, ['role' => Space::ROLE_ACCOUNTANT]);

        $response = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", [
            'source_account_id' => $this->accPj,
            'destination_space_id' => $this->pf->id,
            'destination_account_id' => $this->accPf,
            'amount' => '100.00',
            'transferred_at' => '2026-02-15',
        ], ['Idempotency-Key' => 'trf-rbac-1']);

        $response->assertForbidden();
    }

    public function test_cross_space_transfer_replay_is_idempotent(): void
    {
        $payload = [
            'source_account_id' => $this->accPj,
            'destination_space_id' => $this->pf->id,
            'destination_account_id' => $this->accPf,
            'amount' => '500.00',
            'transferred_at' => '2026-02-15',
            'notes' => 'Reembolso mensal',
        ];

        $res1 = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", $payload, ['Idempotency-Key' => 'trf-idem-cross']);
        $res1->assertCreated();

        $this->assertBalance($this->pj, $this->accPj, '9500.00');
        $this->assertBalance($this->pf, $this->accPf, '1500.00');

        // Replay com mesmos dados
        $res2 = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", $payload, ['Idempotency-Key' => 'trf-idem-cross']);
        $res2->assertOk()->assertJsonPath('replayed', true);

        // Não duplica movimentações nem saldos
        $this->assertBalance($this->pj, $this->accPj, '9500.00');
        $this->assertBalance($this->pf, $this->accPf, '1500.00');

        // Replay divergente dá conflito 409
        $diffPayload = $payload;
        $diffPayload['amount'] = '600.00';
        $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", $diffPayload, ['Idempotency-Key' => 'trf-idem-cross'])
            ->assertStatus(409);
    }

    public function test_reversal_of_cross_space_transfer_restores_balances_and_audits(): void
    {
        $createRes = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", [
            'source_account_id' => $this->accPj,
            'destination_space_id' => $this->pf->id,
            'destination_account_id' => $this->accPf,
            'amount' => '1500.00',
            'transferred_at' => '2026-02-15',
            'notes' => 'Transferência para estorno',
        ], ['Idempotency-Key' => 'trf-para-estorno']);

        $createRes->assertCreated();
        $transferId = $createRes->json('data.id');

        $this->assertBalance($this->pj, $this->accPj, '8500.00');
        $this->assertBalance($this->pf, $this->accPf, '2500.00');

        // Estorno coordenado
        $revRes = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers/{$transferId}/reversal", [
            'reason' => 'Lançamento duplicado no banco externo',
        ], ['Idempotency-Key' => 'rev-trf-1']);

        $revRes->assertCreated()
            ->assertJsonPath('data.is_reversed', true)
            ->assertJsonPath('data.reversal.reason', 'Lançamento duplicado no banco externo');

        // Saldos restaurados exatamente
        $this->assertBalance($this->pj, $this->accPj, '10000.00');
        $this->assertBalance($this->pf, $this->accPf, '1000.00');

        // Auditoria e registros no banco
        $reversal = TransferReversal::query()->where('transfer_id', $transferId)->first();
        $this->assertNotNull($reversal);
        $this->assertSame('Lançamento duplicado no banco externo', $reversal->reason);
        $this->assertSame($this->user->id, $reversal->user_id);

        // Movimentações compensatórias em account_movements
        $movements = AccountMovement::query()->where('transfer_reversal_id', $reversal->id)->get();
        $this->assertCount(2, $movements);

        $compPj = $movements->firstWhere('account_id', $this->accPj);
        $compPf = $movements->firstWhere('account_id', $this->accPf);

        $this->assertNotNull($compPj);
        $this->assertSame(150000, $compPj->amount_cents); // Crédito compensando a saída

        $this->assertNotNull($compPf);
        $this->assertSame(-150000, $compPf->amount_cents); // Débito compensando a entrada

        // Não permite estornar novamente (422)
        $this->api('POST', "/api/spaces/{$this->pj->id}/transfers/{$transferId}/reversal", [
            'reason' => 'Tentativa de estornar de novo',
        ], ['Idempotency-Key' => 'rev-trf-dup'])->assertStatus(422);

        // Replay do estorno com mesma chave é idempotente
        $this->api('POST', "/api/spaces/{$this->pj->id}/transfers/{$transferId}/reversal", [
            'reason' => 'Lançamento duplicado no banco externo',
        ], ['Idempotency-Key' => 'rev-trf-1'])->assertOk()->assertJsonPath('replayed', true);
    }

    public function test_operator_cannot_reverse_transfer(): void
    {
        $createRes = $this->api('POST', "/api/spaces/{$this->pj->id}/transfers", [
            'source_account_id' => $this->accPj,
            'destination_space_id' => $this->pf->id,
            'destination_account_id' => $this->accPf,
            'amount' => '100.00',
            'transferred_at' => '2026-02-15',
        ], ['Idempotency-Key' => 'trf-for-op']);

        $transferId = $createRes->json('data.id');

        // Usuário vira operador em PJ
        $this->pj->members()->updateExistingPivot($this->user->id, ['role' => Space::ROLE_OPERATOR]);

        $this->api('POST', "/api/spaces/{$this->pj->id}/transfers/{$transferId}/reversal", [
            'reason' => 'Operador tentando estorno',
        ], ['Idempotency-Key' => 'rev-op-1'])->assertForbidden();
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

    private function assertBalance(Space $space, int $account, string $expected): void
    {
        $this->api('GET', "/api/spaces/{$space->id}/accounts/{$account}")
            ->assertJsonPath('data.balance', $expected);
    }
}
