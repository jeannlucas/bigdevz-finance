<?php

namespace Tests\Feature;

use App\Actions\Receivables\CreateAgreement;
use App\Models\Account;
use App\Models\ObligationChange;
use App\Models\Payable;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PartialPaymentsAndReceiptsAuditTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $operator;

    private Space $pjSpace;

    private Account $account;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create(['name' => 'Gestor PJ']);
        $this->operator = User::factory()->create(['name' => 'Operador PJ']);

        $this->pjSpace = $this->admin->spaces()->where('kind', Space::PJ)->firstOrFail();
        $this->pjSpace->members()->attach([
            $this->operator->id => ['role' => Space::ROLE_OPERATOR],
        ]);

        $this->account = $this->pjSpace->accounts()->create([
            'name' => 'Conta Corrente PJ',
            'opening_balance_cents' => 1000000, // R$ 10.000,00
            'opening_balance_date' => '2026-01-01',
        ]);
    }

    public function test_partial_payment_lifecycle_audit_and_independent_reversal(): void
    {
        Sanctum::actingAs($this->admin);

        // 1. Criar conta a pagar de R$ 500,00
        $payableRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables", [
            'kind' => 'single',
            'description' => 'Serviços de Manutenção',
            'amount' => '500.00',
            'due_date' => '2026-03-15',
        ], ['Idempotency-Key' => 'pay-part-create-1']);
        $payableRes->assertStatus(201);
        $payableId = $payableRes->json('data.payables.0.id');

        // 2. Realizar primeiro pagamento parcial de R$ 200,00
        $pay1Res = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables/{$payableId}/payments", [
            'account_id' => $this->account->id,
            'amount' => '200.00',
            'paid_on' => '2026-03-10',
        ], ['Idempotency-Key' => 'pay-part-p1']);
        $pay1Res->assertCreated();
        $payment1Id = $pay1Res->json('data.payment.id');

        // Valida estado parcial do payable
        $payable = Payable::findOrFail($payableId);
        $this->assertSame('partial', $payable->status());
        $this->assertSame(20000, $payable->paid_cents);
        $this->assertSame(30000, $payable->remainingCents());

        // Valida que o evento de pagamento foi registrado na auditoria com antes e depois
        $auditPayment = ObligationChange::where('subject', 'payment')
            ->where('subject_id', $payment1Id)
            ->where('action', 'payment')
            ->first();
        $this->assertNotNull($auditPayment);
        $this->assertEquals(50000, $auditPayment->before['remaining_cents']);
        $this->assertEquals(30000, $auditPayment->after['remaining_cents']);

        // 3. Tentar pagar valor que excede o restante (R$ 350,00 > R$ 300,00) -> deve ser rejeitado com 422
        $payExceedRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables/{$payableId}/payments", [
            'account_id' => $this->account->id,
            'amount' => '350.00',
            'paid_on' => '2026-03-11',
        ], ['Idempotency-Key' => 'pay-part-exceed']);
        $payExceedRes->assertStatus(422);

        // 4. Pagar os R$ 300,00 restantes
        $pay2Res = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables/{$payableId}/payments", [
            'account_id' => $this->account->id,
            'amount' => '300.00',
            'paid_on' => '2026-03-12',
        ], ['Idempotency-Key' => 'pay-part-p2']);
        $pay2Res->assertCreated();
        $payment2Id = $pay2Res->json('data.payment.id');

        $payable->refresh();
        $this->assertSame('paid', $payable->status());
        $this->assertSame(50000, $payable->paid_cents);
        $this->assertSame(0, $payable->remainingCents());

        // 5. Estornar apenas o primeiro pagamento (R$ 200,00) de forma independente
        $revRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/payments/{$payment1Id}/reversal", [
            'reason' => 'Erro de digitação da baixa bancária',
        ], ['Idempotency-Key' => 'pay-part-rev1']);
        $revRes->assertCreated();

        // O payable volta a ser parcial, restante volta para R$ 200,00, mantendo o segundo pagamento de R$ 300,00
        $payable->refresh();
        $this->assertSame('partial', $payable->status());
        $this->assertSame(30000, $payable->paid_cents);
        $this->assertSame(20000, $payable->remainingCents());

        // Auditoria registrou o estorno como operação crítica
        $auditReversal = ObligationChange::where('subject', 'payment')
            ->where('subject_id', $payment1Id)
            ->where('action', 'reverse')
            ->first();
        $this->assertNotNull($auditReversal);
        $this->assertTrue($auditReversal->isCritical());
        $this->assertSame('Erro de digitação da baixa bancária', $auditReversal->reason);
    }

    public function test_partial_receipt_lifecycle_audit_and_independent_reversal(): void
    {
        Sanctum::actingAs($this->admin);

        // 1. Criar acordo com parcela de R$ 1.000,00
        $creator = app(CreateAgreement::class);
        $agreement = $creator->handle(
            $this->pjSpace,
            'Consultoria Empresarial',
            '1000.00',
            1,
            '2026-04-10'
        );
        $installment = $agreement->installments()->firstOrFail();

        // 2. Realizar primeiro recebimento parcial de R$ 400,00
        $rec1Res = $this->postJson("/api/spaces/{$this->pjSpace->id}/installments/{$installment->id}/receipts", [
            'account_id' => $this->account->id,
            'amount' => '400.00',
            'received_on' => '2026-04-05',
        ], ['Idempotency-Key' => 'rec-part-r1']);
        $rec1Res->assertCreated();
        $receipt1Id = $rec1Res->json('data.receipt.id');

        $installment->refresh();
        $this->assertSame('partial', $installment->status());
        $this->assertSame(40000, $installment->received_cents);
        $this->assertSame(60000, $installment->remainingCents());

        // Auditoria registrou recebimento
        $auditReceipt = ObligationChange::where('subject', 'receipt')
            ->where('subject_id', $receipt1Id)
            ->where('action', 'receive')
            ->first();
        $this->assertNotNull($auditReceipt);
        $this->assertEquals(100000, $auditReceipt->before['remaining_cents']);
        $this->assertEquals(60000, $auditReceipt->after['remaining_cents']);

        // 3. Tentar receber valor que excede restante (R$ 700,00 > R$ 600,00)
        $recExceed = $this->postJson("/api/spaces/{$this->pjSpace->id}/installments/{$installment->id}/receipts", [
            'account_id' => $this->account->id,
            'amount' => '700.00',
            'received_on' => '2026-04-06',
        ], ['Idempotency-Key' => 'rec-part-exceed']);
        $recExceed->assertStatus(422);

        // 4. Receber restante de R$ 600,00
        $rec2Res = $this->postJson("/api/spaces/{$this->pjSpace->id}/installments/{$installment->id}/receipts", [
            'account_id' => $this->account->id,
            'amount' => '600.00',
            'received_on' => '2026-04-07',
        ], ['Idempotency-Key' => 'rec-part-r2']);
        $rec2Res->assertCreated();

        $installment->refresh();
        $this->assertSame('paid', $installment->status());
        $this->assertSame(100000, $installment->received_cents);
        $this->assertSame(0, $installment->remainingCents());

        // 5. Estornar apenas o primeiro recebimento (R$ 400,00)
        $revRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/receipts/{$receipt1Id}/reversal", [
            'reason' => 'Cheque devolvido pelo banco',
        ], ['Idempotency-Key' => 'rec-part-rev1']);
        $revRes->assertCreated();

        $installment->refresh();
        $this->assertSame('partial', $installment->status());
        $this->assertSame(60000, $installment->received_cents);
        $this->assertSame(40000, $installment->remainingCents());

        $auditReversal = ObligationChange::where('subject', 'receipt')
            ->where('subject_id', $receipt1Id)
            ->where('action', 'reverse')
            ->first();
        $this->assertNotNull($auditReversal);
        $this->assertTrue($auditReversal->isCritical());
        $this->assertSame('Cheque devolvido pelo banco', $auditReversal->reason);
    }

    public function test_partial_reversal_blocked_for_operator_and_retroactive_blocked_by_closed_period(): void
    {
        Sanctum::actingAs($this->admin);

        // 1. Cria conta a pagar de R$ 300,00 e realiza pagamento parcial de R$ 100,00
        $payableRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables", [
            'kind' => 'single',
            'description' => 'Serviços Gerais',
            'amount' => '300.00',
            'due_date' => '2026-05-15',
        ], ['Idempotency-Key' => 'pay-rbac-create']);
        $payableId = $payableRes->json('data.payables.0.id');

        $payRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables/{$payableId}/payments", [
            'account_id' => $this->account->id,
            'amount' => '100.00',
            'paid_on' => '2026-05-10',
        ], ['Idempotency-Key' => 'pay-rbac-p1']);
        $paymentId = $payRes->json('data.payment.id');

        // 2. Operador tenta estornar o pagamento -> deve receber 403 Forbidden
        Sanctum::actingAs($this->operator);
        $opRevRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/payments/{$paymentId}/reversal", [
            'reason' => 'Tentativa não autorizada pelo operador',
        ], ['Idempotency-Key' => 'pay-rbac-op-rev']);
        $opRevRes->assertForbidden();

        // 3. Administrador fecha o período contábil até 2026-05-31
        Sanctum::actingAs($this->admin);
        $closeRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/closing", [
            'closed_until' => '2026-05-31',
            'reason' => 'Fechamento de maio',
        ]);
        $closeRes->assertOk();

        // 4. Tentativa de efetuar novo pagamento com data retroativa no período fechado -> 422 Unprocessable Entity
        $closedPayRes = $this->postJson("/api/spaces/{$this->pjSpace->id}/payables/{$payableId}/payments", [
            'account_id' => $this->account->id,
            'amount' => '50.00',
            'paid_on' => '2026-05-20',
        ], ['Idempotency-Key' => 'pay-closed-fail']);
        $closedPayRes->assertStatus(422);
        $this->assertStringContainsString('Período contábil fechado até 31/05/2026', $closedPayRes->json('message'));
    }
}
