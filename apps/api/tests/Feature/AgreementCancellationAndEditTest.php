<?php

namespace Tests\Feature;

use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Tests\TestCase;

class AgreementCancellationAndEditTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->postJson('/api/auth/login', [
            'email' => $this->user->email,
            'password' => 'password',
            'device_name' => 'teste',
        ])->assertOk()->json('token');
    }

    public function test_can_cancel_open_agreement_without_receipts(): void
    {
        $agreementId = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Venda de Item Teste',
            'total' => '300.00',
            'installment_count' => 3,
            'first_due_date' => '2026-12-10',
        ])->assertCreated()->json('data.id');

        // Cancelamento com justificativa
        $response = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements/{$agreementId}/cancel", [
            'reason' => 'Lançado por engano',
        ])->assertOk();

        $this->assertTrue($response->json('data.is_cancelled'));
        $this->assertSame('Lançado por engano', $response->json('data.cancel_reason'));
        $this->assertNotNull($response->json('data.cancelled_at'));

        // Não aparece mais na listagem de abertos
        $open = $this->api('GET', "/api/spaces/{$this->pf->id}/agreements?status=open")->assertOk()->json('data');
        $this->assertFalse(collect($open)->contains('id', $agreementId));

        // Aparece na listagem geral 'all'
        $all = $this->api('GET', "/api/spaces/{$this->pf->id}/agreements?status=all")->assertOk()->json('data');
        $this->assertTrue(collect($all)->contains('id', $agreementId));
    }

    public function test_cannot_cancel_agreement_with_active_receipt(): void
    {
        $accountId = $this->api('POST', "/api/spaces/{$this->pf->id}/accounts", [
            'name' => 'Conta Corrente',
            'opening_balance' => '1000.00',
            'opening_balance_date' => '2026-01-01',
        ])->assertCreated()->json('data.id');

        $agreement = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Serviço Prestado',
            'total' => '200.00',
            'installment_count' => 2,
            'first_due_date' => '2026-12-10',
        ])->assertCreated()->json('data');

        $installmentId = $agreement['installments'][0]['id'];

        // Registra recebimento
        $this->api('POST', "/api/spaces/{$this->pf->id}/installments/{$installmentId}/receipts", [
            'account_id' => $accountId,
            'amount' => '100.00',
            'received_on' => '2026-11-09',
        ], ['Idempotency-Key' => 'test-cancel-rcpt-1'])->assertCreated();

        // Tenta cancelar: deve ser recusado
        $this->api('POST', "/api/spaces/{$this->pf->id}/agreements/{$agreement['id']}/cancel", [
            'reason' => 'Tentativa indevida',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('agreement');
    }

    public function test_can_edit_open_agreement_metadata(): void
    {
        $category = $this->api('POST', "/api/spaces/{$this->pf->id}/categories", [
            'name' => 'Consultoria',
            'type' => 'income',
        ])->assertCreated()->json('data.id');

        $agreementId = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Descricao Original',
            'total' => '500.00',
            'installment_count' => 1,
            'first_due_date' => '2026-12-15',
        ])->assertCreated()->json('data.id');

        $response = $this->api('PATCH', "/api/spaces/{$this->pf->id}/agreements/{$agreementId}", [
            'description' => 'Descricao Corrigida',
            'category_id' => $category,
        ])->assertOk();

        $this->assertSame('Descricao Corrigida', $response->json('data.description'));
        $this->assertSame($category, $response->json('data.category.id'));
        $this->assertNotNull($response->json('data.edited_at'));
    }

    public function test_can_edit_agreement_total_and_recalculate_installments(): void
    {
        $agreementId = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Contrato Original',
            'total' => '300.00',
            'installment_count' => 3,
            'first_due_date' => '2026-12-10',
        ])->assertCreated()->json('data.id');

        // Altera valor de 300.00 para 600.00 e quantidade de parcelas de 3 para 2
        $response = $this->api('PATCH', "/api/spaces/{$this->pf->id}/agreements/{$agreementId}", [
            'total' => '600.00',
            'installment_count' => 2,
            'reason' => 'Ajuste contratual',
        ])->assertOk();

        $this->assertSame('600.00', $response->json('data.total'));
        $this->assertSame(2, $response->json('data.installment_count'));
        $this->assertCount(2, $response->json('data.installments'));
        $this->assertSame('300.00', $response->json('data.installments.0.amount'));
        $this->assertSame('300.00', $response->json('data.installments.1.amount'));
    }

    public function test_cannot_edit_agreement_total_when_has_receipts(): void
    {
        $accountId = $this->api('POST', "/api/spaces/{$this->pf->id}/accounts", [
            'name' => 'Conta Corrente',
            'opening_balance' => '1000.00',
            'opening_balance_date' => '2026-01-01',
        ])->assertCreated()->json('data.id');

        $agreement = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Serviço com Baixa',
            'total' => '400.00',
            'installment_count' => 2,
            'first_due_date' => '2026-11-09',
        ])->assertCreated()->json('data');

        // Recebe primeira parcela
        $this->api('POST', "/api/spaces/{$this->pf->id}/installments/{$agreement['installments'][0]['id']}/receipts", [
            'account_id' => $accountId,
            'amount' => '200.00',
            'received_on' => '2026-11-09',
        ], ['Idempotency-Key' => 'test-edit-rcpt-1'])->assertCreated();

        // Tenta alterar total: deve ser barrado com 422
        $this->api('PATCH', "/api/spaces/{$this->pf->id}/agreements/{$agreement['id']}", [
            'total' => '800.00',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('total');
    }

    public function test_cannot_edit_cancelled_agreement(): void
    {
        $agreementId = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Para Cancelar',
            'total' => '150.00',
            'installment_count' => 1,
            'first_due_date' => '2026-12-20',
        ])->assertCreated()->json('data.id');

        $this->api('POST', "/api/spaces/{$this->pf->id}/agreements/{$agreementId}/cancel", [
            'reason' => 'Erro',
        ])->assertOk();

        $this->api('PATCH', "/api/spaces/{$this->pf->id}/agreements/{$agreementId}", [
            'description' => 'Tentativa de alteracao',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('agreement');
    }

    private function api(string $method, string $uri, array $data = [], array $headers = [])
    {
        return $this->json($method, $uri, $data, array_merge([
            'Authorization' => "Bearer {$this->token}",
        ], $headers));
    }
}
