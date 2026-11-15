<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Testes para liquidação de contas a pagar com juros, multa e desconto (AC-PAY-INT-001..007).
 */
class PayableChargesAndDiscountsTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    private int $accountId;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-03-15 12:00:00', 'America/Sao_Paulo'));
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->postJson('/api/auth/login', [
            'email' => $this->user->email,
            'password' => 'password',
            'device_name' => 'test-device',
        ])->json('token');

        $account = $this->pf->accounts()->create([
            'name' => 'Conta Corrente PF',
            'opening_balance_cents' => 100000, // R$ 1.000,00
            'opening_balance_date' => '2026-01-01',
        ]);
        $this->accountId = $account->id;
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(string $method, string $uri, array $payload = [], array $headers = []): TestResponse
    {
        return $this->json($method, $uri, $payload, ['Authorization' => "Bearer {$this->token}"] + $headers);
    }

    /**
     * AC-PAY-INT-001, AC-PAY-INT-002, AC-PAY-INT-003, AC-PAY-INT-004:
     * Principal R$ 100,00 + Juros R$ 15,00 = Liquidação da conta em R$ 100,00 e Débito de R$ 115,00 na conta bancária.
     */
    public function test_payment_with_interest_debits_total_and_amortizes_principal_exactly(): void
    {
        // 1. Cria conta a pagar de R$ 100,00
        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Boleto Atrasado',
            'amount' => '100.00',
            'due_date' => '2026-03-01',
        ], ['Idempotency-Key' => 'cria-boleto-100'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');

        // 2. Registra pagamento de R$ 100,00 de principal + R$ 15,00 de juros
        $payRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables/{$payableId}/payments", [
            'account_id' => $this->accountId,
            'amount' => '100.00',
            'interest_amount' => '15.00',
            'paid_on' => '2026-03-10',
        ], ['Idempotency-Key' => 'paga-juros-15'])->assertCreated();

        // 3. Valida resposta da API
        $payRes->assertJsonPath('data.payment.amount', '115.00');
        $payRes->assertJsonPath('data.payment.principal', '100.00');
        $payRes->assertJsonPath('data.payment.interest', '15.00');
        $payRes->assertJsonPath('data.payment.total', '115.00');
        $payRes->assertJsonPath('data.payable.status', 'paid');
        $payRes->assertJsonPath('data.payable.remaining', '0.00');
        $payRes->assertJsonPath('data.payable.paid', '100.00');

        // 4. Saldo da conta bancária deve cair de R$ 1.000,00 para R$ 885,00 (-R$ 115,00)
        $payRes->assertJsonPath('data.account.balance', '885.00');
        $account = $this->pf->accounts()->findOrFail($this->accountId);
        $this->assertSame(88500, $account->balanceCents());

        // 5. Movimentação bancária deve ser exatamente -11500 centavos
        $movement = AccountMovement::where('account_id', $this->accountId)
            ->where('payment_id', $payRes->json('data.payment.id'))
            ->first();
        $this->assertNotNull($movement);
        $this->assertSame(-11500, $movement->amount_cents);

        // 6. Registro em payments com colunas discriminadas
        $payment = Payment::findOrFail($payRes->json('data.payment.id'));
        $this->assertSame(10000, $payment->principal_cents);
        $this->assertSame(1500, $payment->interest_cents);
        $this->assertSame(0, $payment->fine_cents);
        $this->assertSame(0, $payment->discount_cents);
        $this->assertSame(11500, $payment->total_cents);
        $this->assertSame(11500, $payment->amount_cents);
    }

    /**
     * AC-PAY-INT-005: Estorno de pagamento com juros recompõe R$ 115,00 na conta bancária e reabre R$ 100,00 na obrigação.
     */
    public function test_reversal_of_payment_with_interest_restores_bank_balance_and_reopens_payable(): void
    {
        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Taxa de Condomínio',
            'amount' => '100.00',
            'due_date' => '2026-03-01',
        ], ['Idempotency-Key' => 'cria-condominio'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');

        $payRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables/{$payableId}/payments", [
            'account_id' => $this->accountId,
            'amount' => '100.00',
            'interest_amount' => '15.00',
            'paid_on' => '2026-03-10',
        ], ['Idempotency-Key' => 'paga-condominio'])->assertCreated();

        $paymentId = $payRes->json('data.payment.id');
        $this->assertSame(88500, $this->pf->accounts()->findOrFail($this->accountId)->balanceCents());

        // Estorno
        $reverseRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payments/{$paymentId}/reversal", [
            'reason' => 'Pagamento efetuado em conta incorreta',
        ], ['Idempotency-Key' => 'estorno-condominio'])->assertCreated();

        // 1. Saldo da conta bancária volta exatamente para R$ 1.000,00 (+R$ 115,00 creditados)
        $account = $this->pf->accounts()->findOrFail($this->accountId);
        $this->assertSame(100000, $account->balanceCents());

        // 2. Obrigação volta para R$ 100,00 em aberto
        $payable = Payable::findOrFail($payableId);
        $this->assertSame('open', $payable->status());
        $this->assertSame(0, $payable->paid_cents);
        $this->assertSame(10000, $payable->remainingCents());

        // 3. Movimentação contábil de estorno criada com +11500 centavos
        $reversalId = $reverseRes->json('data.original.reversal.id');
        $revMovement = AccountMovement::where('payment_reversal_id', $reversalId)->first();
        $this->assertNotNull($revMovement);
        $this->assertSame(11500, $revMovement->amount_cents);
    }

    /**
     * AC-PAY-INT-002: Composição com multa e desconto.
     */
    public function test_payment_with_fine_and_discount_calculates_correct_total(): void
    {
        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Serviço com Desconto e Multa',
            'amount' => '200.00',
            'due_date' => '2026-03-05',
        ], ['Idempotency-Key' => 'cria-servico'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');

        // Principal 200, Juros 10, Multa 5, Desconto 20 => Total debitado = 195.00
        $payRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables/{$payableId}/payments", [
            'account_id' => $this->accountId,
            'amount' => '200.00',
            'interest_amount' => '10.00',
            'fine_amount' => '5.00',
            'discount_amount' => '20.00',
            'paid_on' => '2026-03-10',
        ], ['Idempotency-Key' => 'paga-servico'])->assertCreated();

        $payRes->assertJsonPath('data.payment.amount', '195.00');
        $payRes->assertJsonPath('data.payment.total', '195.00');
        $payRes->assertJsonPath('data.payment.discount', '20.00');

        $payment = Payment::findOrFail($payRes->json('data.payment.id'));
        $this->assertSame(20000, $payment->principal_cents);
        $this->assertSame(1000, $payment->interest_cents);
        $this->assertSame(500, $payment->fine_cents);
        $this->assertSame(2000, $payment->discount_cents);
        $this->assertSame(19500, $payment->total_cents);

        // Banco debitado em 19500 centavos
        $account = $this->pf->accounts()->findOrFail($this->accountId);
        $this->assertSame(100000 - 19500, $account->balanceCents());
    }

    /**
     * Validações de erro (desconto excessivo, valores negativos, formato).
     */
    public function test_rejects_invalid_charges_or_excessive_discount(): void
    {
        $createRes = $this->api('POST', "/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'single',
            'description' => 'Conta Teste Validação',
            'amount' => '50.00',
            'due_date' => '2026-03-20',
        ], ['Idempotency-Key' => 'cria-val'])->assertCreated();

        $payableId = $createRes->json('data.payables.0.id');

        // Desconto igual ao total (não permitido zerar ou negativar o total)
        $this->api('POST', "/api/spaces/{$this->pf->id}/payables/{$payableId}/payments", [
            'account_id' => $this->accountId,
            'amount' => '50.00',
            'discount_amount' => '50.00',
            'paid_on' => '2026-03-10',
        ], ['Idempotency-Key' => 'paga-desc-igual'])->assertStatus(422);

        // Desconto maior que o subtotal
        $this->api('POST', "/api/spaces/{$this->pf->id}/payables/{$payableId}/payments", [
            'account_id' => $this->accountId,
            'amount' => '50.00',
            'discount_amount' => '60.00',
            'paid_on' => '2026-03-10',
        ], ['Idempotency-Key' => 'paga-desc-maior'])->assertStatus(422);

        // Valor negativo
        $this->api('POST', "/api/spaces/{$this->pf->id}/payables/{$payableId}/payments", [
            'account_id' => $this->accountId,
            'amount' => '50.00',
            'interest_amount' => '-10.00',
            'paid_on' => '2026-03-10',
        ], ['Idempotency-Key' => 'paga-juros-neg'])->assertStatus(422);
    }
}
