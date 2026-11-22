<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\Category;
use App\Models\Payable;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DirectExpenseTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Account $account;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf] = $this->userWithSpaces();
        Sanctum::actingAs($this->user);

        $this->account = $this->pf->accounts()->create([
            'name' => 'Carteira Débito Teste',
            'opening_balance_cents' => 10000, // R$ 100,00
            'opening_balance_date' => '2026-01-01',
        ]);

        $this->category = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Alimentação Fora',
            'type' => 'expense',
            'icon' => 'restaurant',
            'color' => '#FB8C00',
            'is_default' => false,
        ]);
    }

    public function test_can_register_direct_expense_and_debit_account_immediately(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables/direct-expense", [
            'account_id' => $this->account->id,
            'amount' => '35.90',
            'paid_on' => '2026-02-15',
            'description' => 'Almoço no Restaurante',
            'payee' => 'Restaurante Sabor',
            'category_id' => $this->category->id,
        ], [
            'Idempotency-Key' => 'debit-purchase-3590',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.amount', '35.90')
            ->assertJsonPath('data.paid', '35.90')
            ->assertJsonPath('data.remaining', '0.00')
            ->assertJsonPath('data.status', 'paid');

        // 1. Saldo final da conta deve ser exatamente R$ 64,10 (6410 centavos)
        $this->account->refresh();
        $this->assertEquals(6410, $this->account->balanceCents());

        // 2. Extrato deve conter exatamente uma saída de R$ 35,90
        $statementResponse = $this->getJson("/api/spaces/{$this->pf->id}/statement?account_id={$this->account->id}");
        $statementResponse->assertOk();
        $entries = $statementResponse->json('data');
        $this->assertCount(1, $entries);
        $this->assertEquals('35.90', $entries[0]['amount']);
        $this->assertEquals('debit', $entries[0]['direction']);
        $this->assertEquals($this->category->id, $entries[0]['category_id']);

        // 3. Relatório analítico deve conter a despesa
        $summaryResponse = $this->getJson("/api/spaces/{$this->pf->id}/summary");
        $summaryResponse->assertOk()
            ->assertJsonPath('data.payables.open_total', '0.00')
            ->assertJsonPath('data.payables.open_count', 0)
            ->assertJsonPath('data.payables.paid_total', '35.90');

        $expenses = $summaryResponse->json('data.categories_summary.expenses');
        $categorySummary = collect($expenses)->firstWhere('id', $this->category->id);
        $this->assertNotNull($categorySummary);
        $this->assertEquals(3590, $categorySummary['total_cents']);

        // 4. Replay idêntico preserva o resultado
        $replayResponse = $this->postJson("/api/spaces/{$this->pf->id}/payables/direct-expense", [
            'account_id' => $this->account->id,
            'amount' => '35.90',
            'paid_on' => '2026-02-15',
            'description' => 'Almoço no Restaurante',
            'payee' => 'Restaurante Sabor',
            'category_id' => $this->category->id,
        ], [
            'Idempotency-Key' => 'debit-purchase-3590',
        ]);
        $replayResponse->assertOk()
            ->assertJsonPath('idempotency.replayed', true);

        $this->account->refresh();
        $this->assertEquals(6410, $this->account->balanceCents());

        // 5. Payload divergente com a mesma chave retorna 409 Conflict
        $conflictResponse = $this->postJson("/api/spaces/{$this->pf->id}/payables/direct-expense", [
            'account_id' => $this->account->id,
            'amount' => '40.00', // Valor divergente
            'paid_on' => '2026-02-15',
            'description' => 'Almoço no Restaurante',
        ], [
            'Idempotency-Key' => 'debit-purchase-3590',
        ]);
        $conflictResponse->assertStatus(409);
    }

    public function test_reversal_of_direct_expense_restores_balance_and_cancels_obligation(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables/direct-expense", [
            'account_id' => $this->account->id,
            'amount' => '35.90',
            'paid_on' => '2026-02-15',
            'description' => 'Compra Cancelada Débito',
        ], [
            'Idempotency-Key' => 'debit-reversal-test',
        ]);
        $response->assertCreated();
        $payableId = $response->json('data.id');

        $payable = Payable::where('space_id', $this->pf->id)->findOrFail($payableId);
        $payment = $payable->payments()->firstOrFail();

        $this->account->refresh();
        $this->assertEquals(6410, $this->account->balanceCents());

        // Estorno da compra no débito
        $reversalResponse = $this->postJson("/api/spaces/{$this->pf->id}/payments/{$payment->id}/reversal", [
            'reason' => 'Produto devolvido na loja física',
        ], [
            'Idempotency-Key' => 'rev-debit-1',
        ]);
        $reversalResponse->assertCreated();

        // 1. Saldo recomposto aos R$ 100,00
        $this->account->refresh();
        $this->assertEquals(10000, $this->account->balanceCents());

        // 2. Obrigação deve estar cancelada, sem deixar pendência aberta
        $payable->refresh();
        $this->assertTrue($payable->isCancelled());
        $this->assertEquals('cancelled', $payable->status);

        // 3. Resumo deve indicar 0 contas em aberto
        $summary = $this->getJson("/api/spaces/{$this->pf->id}/summary");
        $summary->assertOk()
            ->assertJsonPath('data.payables.open_count', 0)
            ->assertJsonPath('data.payables.open_total', '0.00');
    }

    public function test_direct_expense_accepts_date_field_as_alias_to_paid_on(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/payables/direct-expense", [
            'account_id' => $this->account->id,
            'amount' => '12.50',
            'date' => '2026-02-20', // enviado como date em vez de paid_on
            'description' => 'Lanche Rápido',
        ], [
            'Idempotency-Key' => 'debit-alias-test-1',
        ]);

        $response->assertCreated();
        $this->assertEquals('12.50', $response->json('data.amount'));
        $this->assertEquals('2026-02-20', $response->json('data.due_date'));
    }

    public function test_category_report_increases_by_direct_expense_and_restores_on_reversal(): void
    {
        // 1. Setup hierárquico: Moradia (pai) > Energia (filha)
        $moradia = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Moradia',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E5BB8',
        ]);
        $energia = Category::create([
            'space_id' => $this->pf->id,
            'parent_id' => $moradia->id,
            'name' => 'Energia',
            'type' => 'expense',
            'icon' => 'bolt',
            'color' => '#D97706',
        ]);

        // Três despesas diretas anteriores simulando os R$ 17,70 prévios (3 x R$ 5,90)
        for ($i = 1; $i <= 3; $i++) {
            $this->postJson("/api/spaces/{$this->pf->id}/payables/direct-expense", [
                'account_id' => $this->account->id,
                'amount' => '5.90',
                'paid_on' => '2026-02-01',
                'description' => "Conta de Luz Prévia #$i",
                'category_id' => $energia->id,
            ], [
                'Idempotency-Key' => "pre-expense-$i",
            ])->assertCreated();
        }

        // Total da categoria antes da compra Wise: exatamente R$ 17,70 (1770 centavos)
        $summaryBefore = $this->getJson("/api/spaces/{$this->pf->id}/summary")->json('data.categories_summary.expenses');
        $groupBefore = collect($summaryBefore)->firstWhere('id', $moradia->id);
        $this->assertNotNull($groupBefore);
        $this->assertEquals(1770, $groupBefore['total_cents']);
        $this->assertEquals('17.70', $groupBefore['total']);

        // 2. Compra no débito Wise de R$ 35,90 em Moradia > Energia
        $wiseResponse = $this->postJson("/api/spaces/{$this->pf->id}/payables/direct-expense", [
            'account_id' => $this->account->id,
            'amount' => '35.90',
            'paid_on' => '2026-02-15',
            'description' => 'Conta de Luz da Oficina',
            'category_id' => $energia->id,
        ], [
            'Idempotency-Key' => 'wise-debit-reconcile-test',
        ]);
        $wiseResponse->assertCreated();
        $paymentId = Payable::findOrFail($wiseResponse->json('data.id'))->payments()->firstOrFail()->id;

        // Total da categoria depois da compra Wise: exatamente R$ 53,60 (17.70 + 35.90)
        $summaryDuring = $this->getJson("/api/spaces/{$this->pf->id}/summary")->json('data.categories_summary.expenses');
        $groupDuring = collect($summaryDuring)->firstWhere('id', $moradia->id);
        $this->assertNotNull($groupDuring);
        $this->assertEquals(5360, $groupDuring['total_cents']);
        $this->assertEquals('53.60', $groupDuring['total']);

        // 3. Estorno da compra Wise
        $this->postJson("/api/spaces/{$this->pf->id}/payments/{$paymentId}/reversal", [
            'reason' => 'Devolução da compra no débito',
        ], [
            'Idempotency-Key' => 'wise-rev-reconcile-test',
        ])->assertCreated();

        // Total da categoria depois do estorno: retorna exatamente a R$ 17,70 (1770 centavos)
        $summaryAfter = $this->getJson("/api/spaces/{$this->pf->id}/summary")->json('data.categories_summary.expenses');
        $groupAfter = collect($summaryAfter)->firstWhere('id', $moradia->id);
        $this->assertNotNull($groupAfter);
        $this->assertEquals(1770, $groupAfter['total_cents']);
        $this->assertEquals('17.70', $groupAfter['total']);
    }
}
