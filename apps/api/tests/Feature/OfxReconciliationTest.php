<?php

namespace Tests\Feature;

use App\Actions\Receivables\CreateAgreement;
use App\Models\Account;
use App\Models\Payable;
use App\Models\ReconciledTransaction;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class OfxReconciliationTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Space $space;

    private Account $account;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create(['name' => 'Usuário Conciliação']);
        $this->space = $this->user->spaces()->where('kind', Space::PJ)->firstOrFail();

        $this->account = $this->space->accounts()->create([
            'name' => 'Itaú Conciliação',
            'opening_balance_cents' => 1000000, // R$ 10.000,00
            'opening_balance_date' => '2026-01-01',
        ]);
    }

    public function test_ofx_parse_suggests_matches_and_detects_duplicates(): void
    {
        Sanctum::actingAs($this->user);

        // 1. Cria conta a pagar de R$ 250,00 para data 2026-11-10
        $this->postJson("/api/spaces/{$this->space->id}/payables", [
            'kind' => 'single',
            'description' => 'Conta de Energia',
            'amount' => '250.00',
            'due_date' => '2026-11-10',
        ], ['Idempotency-Key' => 'ofx-payable-1'])->assertCreated();

        // 2. Cria conta a receber de R$ 800,00 para data 2026-11-10
        app(CreateAgreement::class)->handle(
            $this->space,
            'Honorários Mensais',
            '800.00',
            1,
            '2026-11-10'
        );

        // 3. Conteúdo OFX simulando extrato com 1 débito (-250.00) e 1 crédito (+800.00)
        $ofxContent = <<<'OFX'
OFXHEADER:100
DATA:OFXSGML
VERSION:102
<OFX>
<BANKMSGSRSV1>
<STMTTRNRS>
<STMTRS>
<BANKTRANLIST>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261110120000[-03:EST]
<TRNAMT>-250.00
<FITID>TX-DEBIT-001
<MEMO>ELEKTRO ELETRICIDADE
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261110120000[-03:EST]
<TRNAMT>800.00
<FITID>TX-CREDIT-002
<MEMO>PIX RECEBIDO CLIENTE
</STMTTRN>
</BANKTRANLIST>
</STMTRS>
</STMTTRNRS>
</BANKMSGSRSV1>
</OFX>
OFX;

        $parseRes = $this->postJson("/api/spaces/{$this->space->id}/ofx/parse", [
            'account_id' => $this->account->id,
            'ofx_content' => $ofxContent,
        ]);
        $parseRes->assertOk();

        $txs = $parseRes->json('data.transactions');
        $this->assertCount(2, $txs);

        // Transação 1: Débito sugerindo match com a Conta a Pagar
        $tx1 = $txs[0];
        $this->assertSame('TX-DEBIT-001', $tx1['fitid']);
        $this->assertSame('debit', $tx1['type']);
        $this->assertEquals(25000, $tx1['amount_cents']);
        $this->assertFalse($tx1['already_reconciled']);
        $this->assertNotNull($tx1['suggested_match']);
        $this->assertSame('payable', $tx1['suggested_match']['type']);
        $this->assertSame('CONTA DE ENERGIA', $tx1['suggested_match']['title']);

        // Transação 2: Crédito sugerindo match com a Parcela a Receber
        $tx2 = $txs[1];
        $this->assertSame('TX-CREDIT-002', $tx2['fitid']);
        $this->assertSame('credit', $tx2['type']);
        $this->assertEquals(80000, $tx2['amount_cents']);
        $this->assertFalse($tx2['already_reconciled']);
        $this->assertNotNull($tx2['suggested_match']);
        $this->assertSame('installment', $tx2['suggested_match']['type']);
        $this->assertStringContainsString('HONORÁRIOS MENSAIS', $tx2['suggested_match']['title']);

        // 4. Conclui conciliação com confirmação humana
        $reconcileRes = $this->postJson("/api/spaces/{$this->space->id}/ofx/reconcile", [
            'account_id' => $this->account->id,
            'transactions' => [
                [
                    'fitid' => 'TX-DEBIT-001',
                    'action' => 'match_payable',
                    'payable_id' => $tx1['suggested_match']['id'],
                    'amount_cents' => 25000,
                    'posted_at' => '2026-11-10',
                    'memo' => 'ELEKTRO ELETRICIDADE',
                ],
                [
                    'fitid' => 'TX-CREDIT-002',
                    'action' => 'match_installment',
                    'installment_id' => $tx2['suggested_match']['id'],
                    'amount_cents' => 80000,
                    'posted_at' => '2026-11-10',
                    'memo' => 'PIX RECEBIDO CLIENTE',
                ],
            ],
        ]);
        $reconcileRes->assertOk();
        $this->assertEquals(2, $reconcileRes->json('data.reconciled_count'));

        // Valida que o Payable agora está PAGO
        $payable = Payable::where('description', 'CONTA DE ENERGIA')->firstOrFail();
        $this->assertSame('paid', $payable->status());
        $this->assertEquals(25000, $payable->paid_cents);

        // Valida que foram gravados 2 registros em reconciled_transactions com os fitids
        $this->assertEquals(2, ReconciledTransaction::where('space_id', $this->space->id)->count());

        // 5. Reenvio do mesmo OFX: agora ambas devem vir marcadas como already_reconciled = true
        $reparseRes = $this->postJson("/api/spaces/{$this->space->id}/ofx/parse", [
            'account_id' => $this->account->id,
            'ofx_content' => $ofxContent,
        ]);
        $reparseRes->assertOk();
        $this->assertEquals(2, $reparseRes->json('data.already_reconciled_count'));
        $this->assertTrue($reparseRes->json('data.transactions.0.already_reconciled'));
        $this->assertTrue($reparseRes->json('data.transactions.1.already_reconciled'));
    }
}
