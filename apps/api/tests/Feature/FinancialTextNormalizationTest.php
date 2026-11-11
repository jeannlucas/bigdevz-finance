<?php

namespace Tests\Feature;

use App\Models\Payable;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class FinancialTextNormalizationTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-03-15 12:00:00', 'America/Sao_Paulo'));
        [$this->user, $this->pf] = $this->userWithSpaces();
        $this->token = $this->postJson('/api/auth/login', [
            'email' => $this->user->email,
            'password' => 'password',
            'device_name' => 'test-device',
        ])->json('token');
    }

    private function headers(string $key = 'norm-key-1'): array
    {
        return [
            'Authorization' => 'Bearer '.$this->token,
            'Idempotency-Key' => $key,
        ];
    }

    public function test_new_payable_normalizes_description_and_payee_to_uppercase(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'mercado central e água',
            'payee' => 'joão da silva',
            'amount' => '150.00',
            'due_date' => '2026-03-20',
        ], $this->headers('pay-norm-1'));

        $response->assertCreated();
        $payableId = $response->json('data.payables.0.id');

        $this->assertDatabaseHas('payables', [
            'id' => $payableId,
            'description' => 'MERCADO CENTRAL E ÁGUA',
            'payee' => 'JOÃO DA SILVA',
        ]);
    }

    public function test_edit_payable_normalizes_description_and_payee_to_uppercase(): void
    {
        $payable = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => 'single',
            'description' => 'ORIGINAL DESCRIPTION',
            'payee' => 'ORIGINAL PAYEE',
            'amount_cents' => 10000,
            'due_date' => '2026-03-20',
        ]);

        $response = $this->patchJson("/api/spaces/{$this->pf->id}/payables/{$payable->id}", [
            'description' => 'conta de luz e força',
            'payee' => 'enel distribuição',
            'reason' => 'correção de texto cadastral',
        ], $this->headers('pay-edit-1'));

        $response->assertOk();

        $this->assertDatabaseHas('payables', [
            'id' => $payable->id,
            'description' => 'CONTA DE LUZ E FORÇA',
            'payee' => 'ENEL DISTRIBUIÇÃO',
        ]);
    }

    public function test_new_agreement_normalizes_description_to_uppercase(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'consultoria e ação jurídica',
            'total' => '2000.00',
            'installment_count' => 2,
            'first_due_date' => '2026-04-10',
        ], $this->headers('agr-norm-1'));

        $response->assertCreated();
        $agreementId = $response->json('data.id');

        $this->assertDatabaseHas('agreements', [
            'id' => $agreementId,
            'description' => 'CONSULTORIA E AÇÃO JURÍDICA',
        ]);
    }

    public function test_edit_agreement_normalizes_description_to_uppercase(): void
    {
        $agreement = $this->pf->agreements()->create([
            'description' => 'ORIGINAL AGREEMENT',
            'total_cents' => 100000,
            'installment_count' => 1,
            'first_due_date' => '2026-04-10',
        ]);

        $response = $this->patchJson("/api/spaces/{$this->pf->id}/agreements/{$agreement->id}", [
            'description' => 'serviço de automação e coração',
            'reason' => 'ajuste de escopo',
        ], $this->headers('agr-edit-1'));

        $response->assertOk();

        $this->assertDatabaseHas('agreements', [
            'id' => $agreement->id,
            'description' => 'SERVIÇO DE AUTOMAÇÃO E CORAÇÃO',
        ]);
    }

    public function test_category_normalizes_name_to_uppercase(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/categories", [
            'name' => 'alimentação e saúde',
            'type' => 'expense',
            'icon' => 'shopping_cart',
            'color' => '#E57373',
        ], $this->headers('cat-norm-1'));

        $response->assertCreated();
        $categoryId = $response->json('data.id');

        $this->assertDatabaseHas('categories', [
            'id' => $categoryId,
            'name' => 'ALIMENTAÇÃO E SAÚDE',
        ]);
    }

    public function test_account_normalizes_name_to_uppercase(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/accounts", [
            'name' => 'banco do brasil poupança',
            'opening_balance' => '500.00',
            'opening_balance_date' => '2026-01-01',
        ], $this->headers('acc-norm-1'));

        $response->assertCreated();
        $accountId = $response->json('data.id');

        $this->assertDatabaseHas('accounts', [
            'id' => $accountId,
            'name' => 'BANCO DO BRASIL POUPANÇA',
        ]);
    }

    public function test_card_normalizes_name_to_uppercase(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/cards", [
            'name' => 'cartão mastercard platinum',
            'due_day' => 10,
        ], $this->headers('card-norm-1'));

        $response->assertCreated();
        $cardId = $response->json('data.id');

        $this->assertDatabaseHas('cards', [
            'id' => $cardId,
            'name' => 'CARTÃO MASTERCARD PLATINUM',
        ]);
    }

    public function test_loan_normalizes_title_and_counterparty_to_uppercase(): void
    {
        $account = $this->pf->accounts()->create([
            'name' => 'CONTA CORRENTE',
            'opening_balance_cents' => 1000000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $response = $this->postJson("/api/spaces/{$this->pf->id}/loans", [
            'kind' => 'taken',
            'title' => 'empréstimo de veículo',
            'counterparty' => 'banco santander s.a.',
            'principal' => '1000.00',
            'total' => '1200.00',
            'installment_count' => 12,
            'first_due_date' => '2026-04-10',
            'disbursement_account_id' => $account->id,
            'disbursed_at' => '2026-03-15',
            'notes' => 'observação detalhada em minúsculas que não deve mudar',
        ], $this->headers('loan-norm-1'));

        $response->assertCreated();
        $loanId = $response->json('data.id');

        $this->assertDatabaseHas('loans', [
            'id' => $loanId,
            'title' => 'EMPRÉSTIMO DE VEÍCULO',
            'counterparty' => 'BANCO SANTANDER S.A.',
            'notes' => 'observação detalhada em minúsculas que não deve mudar',
        ]);
    }

    public function test_sensitive_and_technical_fields_are_never_transformed_to_uppercase(): void
    {
        // 1. E-mail do usuário permanece em minúsculas
        $this->assertEquals(strtolower($this->user->email), $this->user->fresh()->email);

        // 2. Chave de idempotência permanece literal
        $keyString = 'custom-mixedCase-key-123';
        $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'despesa teste',
            'amount' => '50.00',
            'due_date' => '2026-03-20',
        ], [
            'Authorization' => 'Bearer '.$this->token,
            'Idempotency-Key' => $keyString,
        ]);

        $this->assertDatabaseHas('idempotency_keys', [
            'key' => $keyString,
        ]);

        // 3. cancel_reason permanece na redação original
        $agreement = $this->pf->agreements()->create([
            'description' => 'CONTRATO TESTE',
            'total_cents' => 50000,
            'installment_count' => 1,
            'first_due_date' => '2026-04-10',
        ]);

        $cancelReason = 'Cancelado por solicitação do cliente em 15/03';
        $cancelResponse = $this->postJson("/api/spaces/{$this->pf->id}/agreements/{$agreement->id}/cancel", [
            'reason' => $cancelReason,
        ], $this->headers('agr-cancel-1'));

        $cancelResponse->assertOk();

        $this->assertDatabaseHas('agreements', [
            'id' => $agreement->id,
            'cancel_reason' => $cancelReason,
        ]);
    }
}
