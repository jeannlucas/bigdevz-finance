<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\ObligationChange;
use App\Models\Payable;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PartialPaymentsEdgeCasesTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $space;

    private Account $account;

    private Payable $payable;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->space = $this->user->spaces()->where('kind', Space::PJ)->firstOrFail();

        $this->account = $this->space->accounts()->create([
            'name' => 'Conta Corrente',
            'type' => 'checking',
            'opening_balance_cents' => 1000000, // R$ 10.000,00
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->payable = Payable::create([
            'space_id' => $this->space->id,
            'kind' => 'single',
            'description' => 'Serviços Cloud Mensal',
            'payee' => 'Provedor Cloud',
            'amount_cents' => 30000, // R$ 300,00
            'due_date' => '2026-05-10',
        ]);

        Sanctum::actingAs($this->user);
    }

    public function test_multiple_partial_payments_update_residual_balance_and_audit(): void
    {
        // 1ª Baixa parcial: R$ 100,00
        $res1 = $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            [
                'account_id' => $this->account->id,
                'amount' => '100.00',
                'paid_on' => '2026-05-02',
            ],
            ['Idempotency-Key' => 'pay-part-01']
        );
        $res1->assertCreated();
        $this->assertSame(10000, $this->payable->fresh()->paid_cents);
        $this->assertSame(20000, $this->payable->fresh()->remainingCents());

        // 2ª Baixa parcial: R$ 100,00
        $res2 = $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            [
                'account_id' => $this->account->id,
                'amount' => '100.00',
                'paid_on' => '2026-05-05',
            ],
            ['Idempotency-Key' => 'pay-part-02']
        );
        $res2->assertCreated();
        $this->assertSame(20000, $this->payable->fresh()->paid_cents);
        $this->assertSame(10000, $this->payable->fresh()->remainingCents());

        // 3. Verifica extrato com 2 movimentações
        $movements = AccountMovement::query()->where('account_id', $this->account->id)->get();
        $this->assertCount(2, $movements);
        $this->assertSame(-10000, $movements[0]->amount_cents);
        $this->assertSame(-10000, $movements[1]->amount_cents);

        // 4. Verifica auditoria gravou cada baixa com saldo residual correto
        $audits = ObligationChange::query()->where('space_id', $this->space->id)->where('subject', 'payment')->get();
        $this->assertCount(2, $audits);
        $this->assertSame(10000, $audits[0]->after['paid_cents']);
        $this->assertSame(20000, $audits[0]->after['remaining_cents']);
        $this->assertSame(20000, $audits[1]->after['paid_cents']);
        $this->assertSame(10000, $audits[1]->after['remaining_cents']);
    }

    public function test_payment_exactly_equal_to_residual_balance_liquidates_obligation(): void
    {
        // Paga R$ 200,00
        $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '200.00', 'paid_on' => '2026-05-02'],
            ['Idempotency-Key' => 'pay-liq-01']
        )->assertCreated();

        // Paga exatamente os R$ 100,00 restantes
        $res = $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '100.00', 'paid_on' => '2026-05-05'],
            ['Idempotency-Key' => 'pay-liq-02']
        );
        $res->assertCreated();

        $fresh = $this->payable->fresh();
        $this->assertSame(30000, $fresh->paid_cents);
        $this->assertSame(0, $fresh->remainingCents());
    }

    public function test_payment_exceeding_residual_balance_is_rejected_with_422(): void
    {
        // Paga R$ 250,00
        $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '250.00', 'paid_on' => '2026-05-02'],
            ['Idempotency-Key' => 'pay-exc-01']
        )->assertCreated();

        // Tenta pagar R$ 50,01 quando restam R$ 50,00
        $res = $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '50.01', 'paid_on' => '2026-05-05'],
            ['Idempotency-Key' => 'pay-exc-02']
        );

        $res->assertStatus(422)
            ->assertJsonValidationErrors(['amount']);
        $this->assertSame(25000, $this->payable->fresh()->paid_cents);
    }

    public function test_reversing_one_partial_payment_restores_only_its_amount(): void
    {
        // 1ª Baixa: R$ 100,00
        $res1 = $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '100.00', 'paid_on' => '2026-05-02'],
            ['Idempotency-Key' => 'pay-rev-01']
        );
        $payment1Id = $res1->json('data.payment.id');

        // 2ª Baixa: R$ 100,00
        $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '100.00', 'paid_on' => '2026-05-04'],
            ['Idempotency-Key' => 'pay-rev-02']
        );
        $this->assertSame(20000, $this->payable->fresh()->paid_cents);

        // Estorna apenas a 1ª baixa (R$ 100,00)
        $resRev = $this->postJson(
            "/api/spaces/{$this->space->id}/payments/{$payment1Id}/reversal",
            ['reason' => 'Pagamento efetuado em duplicidade parcial'],
            ['Idempotency-Key' => 'rev-part-01']
        );
        $resRev->assertCreated();

        // O saldo pago deve voltar exatamente para R$ 100,00 (referente à 2ª baixa ainda ativa)
        $this->assertSame(10000, $this->payable->fresh()->paid_cents);
        $this->assertSame(20000, $this->payable->fresh()->remainingCents());

        // Extrato da conta: 2 débitos de R$ 100,00 e 1 estorno a crédito de R$ 100,00
        $movements = AccountMovement::query()->where('account_id', $this->account->id)->get();
        $this->assertCount(3, $movements);
        $totalDebits = $movements->where('amount_cents', '<', 0)->sum('amount_cents');
        $totalCredits = $movements->where('amount_cents', '>', 0)->sum('amount_cents');
        $this->assertSame(-20000, $totalDebits);
        $this->assertSame(10000, $totalCredits);
    }

    public function test_reversing_payment_blocked_when_period_is_closed(): void
    {
        $res = $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '100.00', 'paid_on' => '2026-04-10'],
            ['Idempotency-Key' => 'pay-close-01']
        );
        $paymentId = $res->json('data.payment.id');

        // Fecha período contábil até 2026-04-30
        $this->space->update(['closed_until' => '2026-04-30']);

        // Tenta estornar o pagamento de 2026-04-10
        $resRev = $this->postJson(
            "/api/spaces/{$this->space->id}/payments/{$paymentId}/reversal",
            ['reason' => 'Tentativa de estorno em período fechado'],
            ['Idempotency-Key' => 'rev-close-01']
        );

        $resRev->assertStatus(422);
        $this->assertSame(10000, $this->payable->fresh()->paid_cents);
    }

    public function test_rbac_operator_can_pay_partially_but_cannot_reverse(): void
    {
        $operator = User::factory()->create();
        $this->space->members()->attach($operator->id, ['role' => 'operador']);

        Sanctum::actingAs($operator);

        // Operador realiza baixa parcial rotineira (autorizado)
        $res = $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '50.00', 'paid_on' => '2026-05-02'],
            ['Idempotency-Key' => 'pay-op-01']
        );
        $res->assertCreated();
        $paymentId = $res->json('data.payment.id');

        // Operador tenta estornar pagamento (estritamente bloqueado 403)
        $resRev = $this->postJson(
            "/api/spaces/{$this->space->id}/payments/{$paymentId}/reversal",
            ['reason' => 'Tentativa de estorno por operador'],
            ['Idempotency-Key' => 'rev-op-01']
        );
        $resRev->assertForbidden();
    }

    public function test_rbac_accountant_cannot_record_partial_payments(): void
    {
        $accountant = User::factory()->create();
        $this->space->members()->attach($accountant->id, ['role' => 'contador']);

        Sanctum::actingAs($accountant);

        // Contador tenta realizar baixa parcial (bloqueado 403)
        $res = $this->postJson(
            "/api/spaces/{$this->space->id}/payables/{$this->payable->id}/payments",
            ['account_id' => $this->account->id, 'amount' => '50.00', 'paid_on' => '2026-05-02'],
            ['Idempotency-Key' => 'pay-acc-01']
        );
        $res->assertForbidden();
    }
}
