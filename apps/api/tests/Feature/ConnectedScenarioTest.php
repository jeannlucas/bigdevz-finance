<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\Category;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ConnectedScenarioTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf] = $this->userWithSpaces();
        Sanctum::actingAs($this->user);
    }

    public function test_end_to_end_connected_scenario(): void
    {
        // 1. Cadastra conta Wise com saldo inicial de R$ 100,00
        $accResponse = $this->postJson("/api/spaces/{$this->pf->id}/accounts", [
            'name' => 'Wise Global',
            'opening_balance' => '100.00',
            'opening_balance_date' => '2026-03-01',
        ]);
        $accResponse->assertCreated();
        $account = Account::find($accResponse->json('data.id'));
        $this->assertEquals(10000, $account->balanceCents());

        // 2. Cria Categoria Principal e Subcategoria (ex.: Moradia > Energia)
        $parentCat = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Moradia',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E5BB8',
        ]);

        $subCat = Category::create([
            'space_id' => $this->pf->id,
            'parent_id' => $parentCat->id,
            'name' => 'Energia',
            'type' => 'expense',
            'icon' => 'bolt',
            'color' => '#D97706',
        ]);

        // 3. Registra despesa paga de R$ 35,90 na subcategoria
        $directResponse = $this->postJson("/api/spaces/{$this->pf->id}/payables/direct-expense", [
            'account_id' => $account->id,
            'amount' => '35.90',
            'paid_on' => '2026-03-10',
            'description' => 'Conta de luz da oficina',
            'category_id' => $subCat->id,
        ], [
            'Idempotency-Key' => 'connected-scenario-3590',
        ]);
        $directResponse->assertCreated();
        $payableId = $directResponse->json('data.id');

        // 4. Confere saldo da conta Wise resultante: R$ 64,10 (6410 centavos)
        $account->refresh();
        $this->assertEquals(6410, $account->balanceCents());

        // 5. Confere saída única no extrato
        $movements = $account->movements()->get();
        $this->assertCount(1, $movements);
        $this->assertTrue($movements->first()->isDebit());
        $this->assertEquals(-3590, $movements->first()->amount_cents);

        $statementResponse = $this->getJson("/api/spaces/{$this->pf->id}/statement?account_id={$account->id}");
        $statementResponse->assertOk();
        $this->assertEquals('debit', $statementResponse->json('data.0.direction'));
        $this->assertEquals('35.90', $statementResponse->json('data.0.amount'));

        // 6. Confere composição do relatório (hierarquia sem duplicidade)
        $summaryResponse = $this->getJson("/api/spaces/{$this->pf->id}/summary?month=2026-03");
        $summaryResponse->assertOk();
        $expenses = $summaryResponse->json('data.categories_summary.expenses');
        $moradiaSummary = collect($expenses)->firstWhere('id', $parentCat->id);
        $this->assertNotNull($moradiaSummary);
        $this->assertEquals('35.90', $moradiaSummary['total']);
        $this->assertEquals(3590, $moradiaSummary['total_cents']);
        $this->assertTrue($moradiaSummary['has_children']);
        $this->assertCount(1, $moradiaSummary['composition']);
        $this->assertEquals('ENERGIA', $moradiaSummary['composition'][0]['name']);
        $this->assertEquals(3590, $moradiaSummary['composition'][0]['total_cents']);

        // 7. Estorno da compra recompõe os R$ 100,00 originais e cancela o payable
        $payment = Payment::where('payable_id', $payableId)->first();
        $this->assertNotNull($payment);

        $reversalResponse = $this->postJson("/api/spaces/{$this->pf->id}/payments/{$payment->id}/reversal", [
            'reason' => 'Cobrança indevida estornada pelo estabelecimento',
        ], [
            'Idempotency-Key' => 'connected-scenario-reversal',
        ]);
        $reversalResponse->assertCreated();

        // Saldo recomposto exatamente para R$ 100,00 (10000 centavos)
        $account->refresh();
        $this->assertEquals(10000, $account->balanceCents());

        // Payable cancelado automaticamente sem obrigação residual aberta
        $payable = Payable::find($payableId);
        $this->assertTrue($payable->isCancelled());
        $this->assertEquals('cancelled', $payable->status);
        $this->assertNotNull($payable->cancelled_at);

        // Extrato agora tem a movimentação inversa de estorno (auditoria contábil completa)
        $this->assertCount(2, $account->movements()->get());
        $inMovement = $account->movements()->where('amount_cents', '>', 0)->first();
        $this->assertNotNull($inMovement);
        $this->assertTrue($inMovement->isCredit());
        $this->assertEquals(3590, $inMovement->amount_cents);
    }
}
