<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\Agreement;
use App\Models\Installment;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RecurringReceivableTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private Account $account;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        Sanctum::actingAs($this->user);

        $this->account = $this->pf->accounts()->create([
            'name' => 'Conta Corrente Principal',
            'opening_balance_cents' => 100000, // R$ 1.000,00
            'opening_balance_date' => '2026-01-01',
        ]);
    }

    public function test_recurring_occurrences_are_not_replaced_by_the_installment_editor(): void
    {
        $agreementId = $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Série a preservar',
            'is_variable' => false,
            'amount' => '2500.00',
            'start_date' => '2026-01-15',
            'approved_until' => '2026-03-01',
            'confirm_past' => true,
        ], ['Idempotency-Key' => 'recurring-protected-edit'])->assertCreated()->json('data.id');

        $agreement = Agreement::findOrFail($agreementId);
        $ids = $agreement->installments()->orderBy('number')->pluck('id')->all();

        $this->patchJson("/api/spaces/{$this->pf->id}/agreements/{$agreementId}", [
            'total' => '3000.00',
            'installment_count' => 2,
            'first_due_date' => '2026-01-15',
        ])->assertUnprocessable();

        $this->assertSame($ids, $agreement->installments()->orderBy('number')->pluck('id')->all());
    }

    /**
     * AC-FIN-034: Suporte a receita recorrente mensal fixa.
     * O cadastro gera as ocorrências até o horizonte aprovado e NÃO altera o saldo bancário.
     */
    public function test_can_create_fixed_monthly_recurring_receivable_and_generate_installments(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Contrato de Consultoria Mensal',
            'is_variable' => false,
            'amount' => '2500.00',
            'start_date' => '2026-01-15',
            'approved_until' => '2026-03-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'rec-fixed-consultoria-1',
        ]);

        $response->assertCreated();

        $agreement = Agreement::where('space_id', $this->pf->id)
            ->where('description', 'CONTRATO DE CONSULTORIA MENSAL')
            ->firstOrFail();

        $this->assertEquals('recurring', $agreement->kind);
        $this->assertFalse((bool) $agreement->is_variable);
        $this->assertEquals(250000, $agreement->amount_cents);
        $this->assertEquals('2026-01-15', $agreement->start_date->toDateString());
        $this->assertEquals(15, $agreement->reference_day);

        // Verifica as ocorrências geradas: janeiro, fevereiro e março de 2026 (3 ciclos)
        $installments = $agreement->installments()->orderBy('number')->get();
        $this->assertCount(3, $installments);

        $this->assertEquals('2026-01-15', $installments[0]->due_date->toDateString());
        $this->assertEquals(250000, $installments[0]->amount_cents);
        $this->assertEquals('2026-01-01', $installments[0]->cycle->toDateString());

        $this->assertEquals('2026-02-15', $installments[1]->due_date->toDateString());
        $this->assertEquals(250000, $installments[1]->amount_cents);
        $this->assertEquals('2026-02-01', $installments[1]->cycle->toDateString());

        $this->assertEquals('2026-03-15', $installments[2]->due_date->toDateString());
        $this->assertEquals(250000, $installments[2]->amount_cents);
        $this->assertEquals('2026-03-01', $installments[2]->cycle->toDateString());

        // Regra inegociável: projeção orçamentária NÃO altera saldo bancário
        $this->assertEquals(100000, $this->account->fresh()->balanceCents());
    }

    /**
     * AC-FIN-034: Recorrência variável sem valor inicial.
     * Todas as ocorrências nascem com amount_cents = null e status = awaiting_amount.
     */
    public function test_can_create_variable_recurring_receivable_without_initial_amount(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Honorários Variáveis por Êxito',
            'is_variable' => true,
            'estimated_amount' => '3000.00',
            'start_date' => '2026-01-10',
            'approved_until' => '2026-02-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'rec-var-honorarios-1',
        ]);

        $response->assertCreated();

        $agreement = Agreement::where('space_id', $this->pf->id)
            ->where('description', 'HONORÁRIOS VARIÁVEIS POR ÊXITO')
            ->firstOrFail();

        $this->assertEquals('recurring', $agreement->kind);
        $this->assertTrue((bool) $agreement->is_variable);
        $this->assertNull($agreement->amount_cents);
        $this->assertEquals(300000, $agreement->estimated_amount_cents);

        $installments = $agreement->installments()->orderBy('number')->get();
        $this->assertCount(2, $installments); // 2026-01-10 e 2026-02-10

        foreach ($installments as $inst) {
            $this->assertNull($inst->amount_cents);
            $this->assertEquals(300000, $inst->estimated_amount_cents);
            $this->assertEquals('awaiting_amount', $inst->status());
        }
    }

    /**
     * AC-FIN-034: Recorrência variável com valor inicial informado (seguindo PEND-002 / AC-FIN-031).
     * O valor inicial aplica-se estritamente à 1ª ocorrência (due_date == start_date);
     * ocorrências posteriores nascem com amount_cents = null e awaiting_amount.
     */
    public function test_can_create_variable_recurring_receivable_with_initial_amount_for_first_cycle(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Serviços de Manutenção com 1ª Parcela Definida',
            'is_variable' => true,
            'amount' => '362.05',
            'estimated_amount' => '350.00',
            'start_date' => '2026-01-10',
            'approved_until' => '2026-02-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'rec-var-with-initial-1',
        ]);

        $response->assertCreated();

        $agreement = Agreement::where('space_id', $this->pf->id)
            ->where('description', 'SERVIÇOS DE MANUTENÇÃO COM 1ª PARCELA DEFINIDA')
            ->firstOrFail();

        $installments = $agreement->installments()->orderBy('number')->get();
        $this->assertCount(2, $installments);

        // 1ª ocorrência: valor confirmado de R$ 362,05 (36205 centavos)
        $this->assertEquals(36205, $installments[0]->amount_cents);
        $this->assertEquals('pending', $installments[0]->status());

        // 2ª ocorrência: awaiting_amount
        $this->assertNull($installments[1]->amount_cents);
        $this->assertEquals('awaiting_amount', $installments[1]->status());
    }

    /**
     * AC-FIN-035: Preservação de vencimento em meses curtos e ano bissexto (MonthlyDate::shift).
     * Início em 31/01/2026 -> 28/02/2026 -> 31/03/2026 -> 30/04/2026.
     */
    public function test_recurring_receivable_preserves_reference_day_in_short_months(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Mensalidade Dia 31',
            'is_variable' => false,
            'amount' => '100.00',
            'start_date' => '2026-01-31',
            'approved_until' => '2026-04-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'rec-preserve-day-31',
        ]);

        $response->assertCreated();

        $agreement = Agreement::where('space_id', $this->pf->id)
            ->where('description', 'MENSALIDADE DIA 31')
            ->firstOrFail();

        $installments = $agreement->installments()->orderBy('number')->get();
        $this->assertCount(4, $installments);

        $this->assertEquals('2026-01-31', $installments[0]->due_date->toDateString());
        $this->assertEquals('2026-02-28', $installments[1]->due_date->toDateString());
        $this->assertEquals('2026-03-31', $installments[2]->due_date->toDateString());
        $this->assertEquals('2026-04-30', $installments[3]->due_date->toDateString());
    }

    /**
     * AC-FIN-036: Liquidação de ocorrência recorrente e movimentação de saldo.
     * Receber parcela credita a conta bancária e atualiza status para quitada.
     */
    public function test_can_receive_recurring_occurrence_and_update_bank_balance(): void
    {
        $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Aluguel Recebido',
            'is_variable' => false,
            'amount' => '1500.00',
            'start_date' => '2026-01-05',
            'approved_until' => '2026-02-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'rec-aluguel-1',
        ])->assertCreated();

        $agreement = Agreement::where('space_id', $this->pf->id)->where('description', 'ALUGUEL RECEBIDO')->firstOrFail();
        $installment = $agreement->installments()->firstOrFail();

        // Recebe a 1ª ocorrência de R$ 1.500,00 na conta bancária
        $receiveResponse = $this->postJson("/api/spaces/{$this->pf->id}/installments/{$installment->id}/receipts", [
            'account_id' => $this->account->id,
            'amount' => '1500.00',
            'received_on' => '2026-01-05',
        ], [
            'Idempotency-Key' => 'receipt-aluguel-1',
        ]);

        $receiveResponse->assertCreated()->assertJsonPath('data.agreement.remaining', '1500.00');

        $installment->refresh();
        $this->assertEquals('paid', $installment->status());
        $this->assertEquals(150000, $installment->received_cents);

        // Saldo bancário incrementado: 1.000,00 + 1.500,00 = 2.500,00 (250000 centavos)
        $this->assertEquals(250000, $this->account->fresh()->balanceCents());
    }

    /**
     * AC-FIN-036: Recebimento de ocorrência variável confirmando o valor no ato da baixa.
     */
    public function test_can_receive_variable_occurrence_confirming_amount_upon_receipt(): void
    {
        $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Consultoria com Valor Variável',
            'is_variable' => true,
            'start_date' => '2026-01-10',
            'approved_until' => '2026-02-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'rec-var-consultoria-1',
        ])->assertCreated();

        $agreement = Agreement::where('space_id', $this->pf->id)->where('description', 'CONSULTORIA COM VALOR VARIÁVEL')->firstOrFail();
        $installment = $agreement->installments()->firstOrFail();
        $this->assertNull($installment->amount_cents);

        // Recebe confirmando R$ 850,00
        $this->postJson("/api/spaces/{$this->pf->id}/installments/{$installment->id}/receipts", [
            'account_id' => $this->account->id,
            'amount' => '850.00',
            'received_on' => '2026-01-10',
        ], [
            'Idempotency-Key' => 'receipt-var-consultoria-1',
        ])->assertCreated();

        $installment->refresh();
        $this->assertEquals(85000, $installment->amount_cents);
        $this->assertEquals(85000, $installment->received_cents);
        $this->assertEquals('paid', $installment->status());

        // Saldo: 1000,00 + 850,00 = 1850,00 (185000)
        $this->assertEquals(185000, $this->account->fresh()->balanceCents());
    }

    /**
     * AC-FIN-036: Estorno de recebimento de receita recorrente restaura saldo e auditoria.
     */
    public function test_can_reverse_recurring_receipt_restoring_balance_and_audit(): void
    {
        $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Mensalidade Estorno',
            'is_variable' => false,
            'amount' => '500.00',
            'start_date' => '2026-01-10',
            'approved_until' => '2026-02-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'rec-estorno-1',
        ])->assertCreated();

        $agreement = Agreement::where('space_id', $this->pf->id)->where('description', 'MENSALIDADE ESTORNO')->firstOrFail();
        $installment = $agreement->installments()->firstOrFail();

        $receiptRes = $this->postJson("/api/spaces/{$this->pf->id}/installments/{$installment->id}/receipts", [
            'account_id' => $this->account->id,
            'amount' => '500.00',
            'received_on' => '2026-01-10',
        ], [
            'Idempotency-Key' => 'receipt-estorno-1',
        ])->assertCreated();

        $receiptId = $receiptRes->json('data.id') ?? $receiptRes->json('id') ?? $receiptRes->json('data.receipt.id');
        $this->assertEquals(150000, $this->account->fresh()->balanceCents());

        // Estorno
        $this->postJson("/api/spaces/{$this->pf->id}/receipts/{$receiptId}/reversal", [
            'reason' => 'Recebimento lançado por engano nesta conta',
        ], [
            'Idempotency-Key' => 'reversal-estorno-1',
        ])->assertCreated();

        // Saldo restaurado para R$ 1.000,00 (100000)
        $this->assertEquals(100000, $this->account->fresh()->balanceCents());

        $installment->refresh();
        $this->assertEquals(0, $installment->received_cents);
        $this->assertEquals('pending', $installment->status());
    }

    /**
     * AC-FIN-035: Idempotência de criação e integridade com Idempotency-Key.
     */
    public function test_generator_is_idempotent_and_replay_returns_existing_agreement(): void
    {
        $payload = [
            'kind' => 'recurring',
            'description' => 'Honorários Contábeis Recorrentes',
            'is_variable' => false,
            'amount' => '1200.00',
            'start_date' => '2026-01-01',
            'approved_until' => '2026-03-01',
            'confirm_past' => true,
        ];

        $res1 = $this->postJson("/api/spaces/{$this->pf->id}/agreements", $payload, [
            'Idempotency-Key' => 'key-idempotent-rec-1',
        ])->assertCreated();

        $agreementId1 = $res1->json('data.id');

        // Replay da mesma requisição com a mesma chave
        $res2 = $this->postJson("/api/spaces/{$this->pf->id}/agreements", $payload, [
            'Idempotency-Key' => 'key-idempotent-rec-1',
        ])->assertOk();

        $agreementId2 = $res2->json('data.id');
        $this->assertEquals($agreementId1, $agreementId2);

        // Nenhuma duplicidade de parcelas geradas
        $count = Installment::where('agreement_id', $agreementId1)->count();
        $this->assertEquals(3, $count);
    }

    /**
     * AC-FIN-034: Isolamento multi-tenant por espaço (PF / PJ).
     */
    public function test_space_isolation_pf_and_pj(): void
    {
        // Cria na PF
        $res = $this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'kind' => 'recurring',
            'description' => 'Receita Isolada PF',
            'is_variable' => false,
            'amount' => '800.00',
            'start_date' => '2026-01-10',
            'approved_until' => '2026-02-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'rec-pf-iso-1',
        ])->assertCreated();

        $agreementId = $res->json('data.id');

        // Tentativa de acessar pela PJ resulta em 404
        $this->getJson("/api/spaces/{$this->pj->id}/agreements/{$agreementId}")
            ->assertNotFound();
    }

    /**
     * AC-FIN-035 / AC-UI-012: Endpoint de prévia de recorrência (sem gravar).
     */
    public function test_recurrence_preview_calculates_plan_and_past_occurrences(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/agreements/recurrence-preview", [
            'amount' => '1500.00',
            'start_date' => '2026-01-10',
            'is_variable' => false,
        ]);

        $response->assertOk();
        $this->assertEquals(10, $response->json('data.reference_day'));
        $this->assertNotEmpty($response->json('data.items'));
        $this->assertEquals('1500.00', $response->json('data.items.0.amount'));
    }
}
