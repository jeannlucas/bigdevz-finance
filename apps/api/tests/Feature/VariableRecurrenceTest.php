<?php

namespace Tests\Feature;

use App\Actions\Payables\GenerateObligations;
use App\Models\Account;
use App\Models\Recurrence;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class VariableRecurrenceTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Account $account;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf] = $this->userWithSpaces();
        Sanctum::actingAs($this->user);

        $this->account = $this->pf->accounts()->create([
            'name' => 'Conta Corrente Principal',
            'opening_balance_cents' => 100000, // R$ 1.000,00
            'opening_balance_date' => '2026-01-01',
        ]);
    }

    public function test_can_create_variable_recurrence_with_optional_estimate(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'recurring',
            'description' => 'Conta de Energia Equatorial',
            'is_variable' => true,
            'estimated_amount' => '150.00',
            'start_date' => '2026-01-10',
            'approved_until' => '2026-03-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'var-rec-create-1',
        ]);

        $response->assertCreated();

        $recurrence = Recurrence::where('space_id', $this->pf->id)
            ->where('description', 'CONTA DE ENERGIA EQUATORIAL')
            ->first();

        $this->assertNotNull($recurrence);
        $this->assertTrue((bool) $recurrence->is_variable);
        $this->assertEquals(15000, $recurrence->estimated_amount_cents);
        $this->assertNull($recurrence->amount_cents);

        // Ocorrências geradas devem ter amount_cents null e estimated_amount_cents 15000
        $occurrences = $recurrence->occurrences()->get();
        $this->assertNotEmpty($occurrences);
        foreach ($occurrences as $occ) {
            $this->assertNull($occ->amount_cents);
            $this->assertEquals(15000, $occ->estimated_amount_cents);
            $this->assertEquals('awaiting_amount', $occ->status);
        }

        // Filtro awaiting_amount deve retornar essas ocorrências
        $listResponse = $this->getJson("/api/spaces/{$this->pf->id}/payables?status=awaiting_amount");
        $listResponse->assertOk();
        $this->assertGreaterThanOrEqual(count($occurrences), count($listResponse->json('data')));
    }

    public function test_can_confirm_amount_of_single_occurrence_and_pay_another_with_different_values(): void
    {
        // Cria recorrência variável com 2 ciclos
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'recurring',
            'description' => 'Energia Elétrica Variável',
            'is_variable' => true,
            'estimated_amount' => '100.00',
            'start_date' => '2026-01-15',
            'approved_until' => '2026-02-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'var-rec-2-cycles',
        ]);
        $response->assertCreated();

        $recurrence = Recurrence::where('space_id', $this->pf->id)
            ->where('description', 'ENERGIA ELÉTRICA VARIÁVEL')
            ->firstOrFail();

        $occurrences = $recurrence->occurrences()->orderBy('due_date')->get();
        $this->assertCount(2, $occurrences);

        $janOccurrence = $occurrences[0];
        $febOccurrence = $occurrences[1];

        // 1. Confirma o valor de janeiro para R$ 50,00 sem pagar
        $patchJan = $this->patchJson("/api/spaces/{$this->pf->id}/payables/{$janOccurrence->id}", [
            'amount' => '50.00',
        ]);
        $patchJan->assertOk()
            ->assertJsonPath('data.amount', '50.00')
            ->assertJsonPath('data.status', 'open');

        $janOccurrence->refresh();
        $this->assertEquals(5000, $janOccurrence->amount_cents);

        // Fevereiro continua aguardando valor
        $febOccurrence->refresh();
        $this->assertNull($febOccurrence->amount_cents);

        // 2. Paga a ocorrência de fevereiro diretamente informando o valor efetivo de R$ 200,00
        $payFeb = $this->postJson("/api/spaces/{$this->pf->id}/payables/{$febOccurrence->id}/payments", [
            'account_id' => $this->account->id,
            'amount' => '200.00',
            'paid_on' => '2026-02-15',
        ], [
            'Idempotency-Key' => 'pay-feb-200',
        ]);
        $payFeb->assertCreated();

        $febOccurrence->refresh();
        $this->assertEquals(20000, $febOccurrence->amount_cents);
        $this->assertEquals(20000, $febOccurrence->paid_cents);
        $this->assertEquals('paid', $febOccurrence->status);

        // Janeiro permanece inalterado em R$ 50,00 e aberto
        $janOccurrence->refresh();
        $this->assertEquals(5000, $janOccurrence->amount_cents);
        $this->assertEquals(0, $janOccurrence->paid_cents);
        $this->assertEquals('open', $janOccurrence->status);

        // Apenas o pagamento de R$ 200,00 alterou o saldo bancário (R$ 1000,00 - R$ 200,00 = R$ 800,00)
        $this->account->refresh();
        $this->assertEquals(80000, $this->account->balanceCents());

        // 3. Reexecução do gerador preserva ambas as ocorrências e seus valores
        app(GenerateObligations::class)->forRecurrence($recurrence, '2026-02-28');

        $this->assertEquals(2, $recurrence->occurrences()->count());
        $janOccurrence->refresh();
        $this->assertEquals(5000, $janOccurrence->amount_cents);
        $febOccurrence->refresh();
        $this->assertEquals(20000, $febOccurrence->amount_cents);
        $this->assertEquals(20000, $febOccurrence->paid_cents);
    }

    public function test_variable_recurrence_without_estimate_works_and_preserves_short_months(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'recurring',
            'description' => 'Serviço Sem Estimativa',
            'is_variable' => true,
            'start_date' => '2026-01-31', // Dia 31 -> Fevereiro deve cair em 28
            'approved_until' => '2026-03-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'var-no-estimate',
        ]);
        $response->assertCreated();

        $recurrence = Recurrence::where('space_id', $this->pf->id)
            ->where('description', 'SERVIÇO SEM ESTIMATIVA')
            ->firstOrFail();

        $this->assertNull($recurrence->estimated_amount_cents);

        $occurrences = $recurrence->occurrences()->orderBy('due_date')->get();
        $this->assertCount(3, $occurrences);
        $this->assertEquals('2026-01-31', $occurrences[0]->due_date->toDateString());
        $this->assertEquals('2026-02-28', $occurrences[1]->due_date->toDateString()); // Mês curto preserva referência
        $this->assertEquals('2026-03-31', $occurrences[2]->due_date->toDateString()); // Março restaura dia 31
    }

    public function test_fixed_recurrence_compatibility(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'recurring',
            'description' => 'Internet Fibra Fixa',
            'amount' => '120.00',
            'start_date' => '2026-01-05',
            'approved_until' => '2026-02-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'fixed-rec-compat',
        ]);
        $response->assertCreated();

        $recurrence = Recurrence::where('space_id', $this->pf->id)
            ->where('description', 'INTERNET FIBRA FIXA')
            ->firstOrFail();

        $this->assertFalse((bool) $recurrence->is_variable);
        $this->assertEquals(12000, $recurrence->amount_cents);

        $occurrences = $recurrence->occurrences()->get();
        $this->assertNotEmpty($occurrences);
        foreach ($occurrences as $occ) {
            $this->assertEquals(12000, $occ->amount_cents);
            $this->assertEquals('open', $occ->status);
        }
    }

    public function test_can_create_variable_recurrence_with_initial_amount_for_first_occurrence(): void
    {
        // PEND-002 / AC-FIN-031: Recorrência variável com valor inicial informado (R$ 362,05)
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables", [
            'kind' => 'recurring',
            'description' => 'Sanepar Água e Esgoto',
            'is_variable' => true,
            'amount' => '362.05', // R$ 362,05 na primeira fatura
            'estimated_amount' => '350.00', // Estimativa opcional
            'start_date' => '2026-11-09',
            'approved_until' => '2027-01-01',
            'confirm_past' => true,
        ], [
            'Idempotency-Key' => 'var-rec-with-initial-amount-1',
        ]);

        $response->assertCreated();

        $recurrence = Recurrence::where('space_id', $this->pf->id)
            ->where('description', 'SANEPAR ÁGUA E ESGOTO')
            ->firstOrFail();

        $this->assertTrue((bool) $recurrence->is_variable);
        $this->assertEquals(36205, $recurrence->amount_cents);
        $this->assertEquals(35000, $recurrence->estimated_amount_cents);

        $occurrences = $recurrence->occurrences()->orderBy('due_date')->get();
        $this->assertCount(3, $occurrences);

        // 1ª ocorrência (2026-11-09): valor inicial confirmado de R$ 362,05
        $firstOcc = $occurrences[0];
        $this->assertEquals('2026-11-09', $firstOcc->due_date->toDateString());
        $this->assertEquals(36205, $firstOcc->amount_cents);
        $this->assertEquals(0, $firstOcc->paid_cents);
        $this->assertContains($firstOcc->status, ['open', 'overdue']);

        // 2ª ocorrência (2026-12-09): continua como awaiting_amount (null)
        $secondOcc = $occurrences[1];
        $this->assertEquals('2026-12-09', $secondOcc->due_date->toDateString());
        $this->assertNull($secondOcc->amount_cents);
        $this->assertEquals('awaiting_amount', $secondOcc->status);

        // 3ª ocorrência (2027-01-09): continua como awaiting_amount (null)
        $thirdOcc = $occurrences[2];
        $this->assertEquals('2027-01-09', $thirdOcc->due_date->toDateString());
        $this->assertNull($thirdOcc->amount_cents);
        $this->assertEquals('awaiting_amount', $thirdOcc->status);

        // Saldo bancário permanece 100% inalterado (R$ 1.000,00)
        $this->account->refresh();
        $this->assertEquals(100000, $this->account->balanceCents());

        // Reexecução do gerador preserva a 1ª ocorrência com R$ 362,05 e não altera as demais
        app(GenerateObligations::class)->forRecurrence($recurrence, '2027-02-01');
        $firstOcc->refresh();
        $this->assertEquals(36205, $firstOcc->amount_cents);
        $secondOcc->refresh();
        $this->assertNull($secondOcc->amount_cents);
        $thirdOcc->refresh();
        $this->assertNull($thirdOcc->amount_cents);
    }
}
