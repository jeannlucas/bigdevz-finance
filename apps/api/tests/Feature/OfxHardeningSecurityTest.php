<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\Category;
use App\Models\ReconciledTransaction;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Http\UploadedFile;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class OfxHardeningSecurityTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $space;

    private Account $account;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create();
        $this->space = $this->user->spaces()->where('kind', Space::PJ)->firstOrFail();

        $this->account = $this->space->accounts()->create([
            'name' => 'Banco Principal',
            'type' => 'checking',
            'opening_balance_cents' => 500000,
            'opening_balance_date' => '2026-01-01',
        ]);

        Sanctum::actingAs($this->user);
    }

    public function test_empty_ofx_content_returns_422(): void
    {
        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/parse",
            [
                'account_id' => $this->account->id,
                'ofx_content' => '   ',
            ]
        );

        $response->assertStatus(422);
    }

    public function test_malformed_ofx_without_stmttrn_returns_422(): void
    {
        $malformed = "OFXHEADER:100\nDATA:OFXSGML\n<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>\n</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>";

        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/parse",
            [
                'account_id' => $this->account->id,
                'ofx_content' => $malformed,
            ]
        );

        $response->assertStatus(422)
            ->assertJsonPath('message', 'Nenhuma transação válida encontrada no arquivo OFX.');
    }

    public function test_parses_both_ofx_1x_and_ofx_2x_formats(): void
    {
        // OFX 1.02 SGML sem fechamento de tags
        $ofxSgml = "OFXHEADER:100\nDATA:OFXSGML\n<STMTTRN>\n<TRNTYPE>DEBIT\n<DTPOSTED>20260410120000\n<TRNAMT>-150.00\n<FITID>SGML001\n<MEMO>Pagamento SGML\n";
        // OFX 2.0 XML com tags fechadas
        $ofxXml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<OFX><STMTTRN><TRNTYPE>CREDIT</TRNTYPE><DTPOSTED>20260411</DTPOSTED><TRNAMT>250.00</TRNAMT><FITID>XML002</FITID><MEMO>Recebimento XML</MEMO></STMTTRN></OFX>";

        $resSgml = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/parse",
            ['account_id' => $this->account->id, 'ofx_content' => $ofxSgml]
        );
        $resSgml->assertOk()
            ->assertJsonPath('data.transactions.0.fitid', 'SGML001')
            ->assertJsonPath('data.transactions.0.type', 'debit')
            ->assertJsonPath('data.transactions.0.amount_cents', 15000);

        $resXml = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/parse",
            ['account_id' => $this->account->id, 'ofx_content' => $ofxXml]
        );
        $resXml->assertOk()
            ->assertJsonPath('data.transactions.0.fitid', 'XML002')
            ->assertJsonPath('data.transactions.0.type', 'credit')
            ->assertJsonPath('data.transactions.0.amount_cents', 25000);
    }

    public function test_handles_iso_8859_1_encoding_with_brazilian_characters_via_upload(): void
    {
        $rawMemo = mb_convert_encoding('Tarifa Concessionária Água & Esgoto', 'ISO-8859-1', 'UTF-8');
        $ofxIso = "OFXHEADER:100\n<STMTTRN>\n<TRNTYPE>DEBIT\n<DTPOSTED>20260410\n<TRNAMT>-85.50\n<FITID>ISO001\n<MEMO>{$rawMemo}\n";

        $file = UploadedFile::fake()->createWithContent('extrato_iso.ofx', $ofxIso);

        $response = $this->post(
            "/api/spaces/{$this->space->id}/ofx/parse",
            [
                'account_id' => $this->account->id,
                'ofx_file' => $file,
            ]
        );

        $response->assertOk()
            ->assertJsonPath('data.transactions.0.fitid', 'ISO001')
            ->assertJsonPath('data.transactions.0.memo', 'Tarifa Concessionária Água & Esgoto');
    }

    public function test_discards_invalid_dates_and_invalid_amounts(): void
    {
        $ofx = "OFXHEADER:100\n"
            // Transação 1: data inexistente 31/02
            ."<STMTTRN>\n<DTPOSTED>20260231\n<TRNAMT>-50.00\n<FITID>INV_DATE\n<MEMO>Data Invalida\n"
            // Transação 2: valor corrupto com letras
            ."<STMTTRN>\n<DTPOSTED>20260410\n<TRNAMT>-ABC\n<FITID>INV_AMT\n<MEMO>Valor Letras\n"
            // Transação 3: valor zero
            ."<STMTTRN>\n<DTPOSTED>20260410\n<TRNAMT>0.00\n<FITID>ZERO_AMT\n<MEMO>Valor Zero\n"
            // Transação 4: valor válido
            ."<STMTTRN>\n<DTPOSTED>20260410\n<TRNAMT>-75.00\n<FITID>VALID_01\n<MEMO>Valor Valido\n";

        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/parse",
            ['account_id' => $this->account->id, 'ofx_content' => $ofx]
        );

        $response->assertOk()
            ->assertJsonPath('data.transactions_count', 1)
            ->assertJsonPath('data.transactions.0.fitid', 'VALID_01');
    }

    public function test_deduplicates_duplicate_fitid_in_same_file(): void
    {
        $ofx = "OFXHEADER:100\n"
            ."<STMTTRN>\n<DTPOSTED>20260410\n<TRNAMT>-100.00\n<FITID>DUPL01\n<MEMO>Lancamento 1\n"
            ."<STMTTRN>\n<DTPOSTED>20260410\n<TRNAMT>-100.00\n<FITID>DUPL01\n<MEMO>Lancamento 2 Duplicado\n";

        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/parse",
            ['account_id' => $this->account->id, 'ofx_content' => $ofx]
        );

        $response->assertOk()
            ->assertJsonPath('data.transactions_count', 1)
            ->assertJsonPath('data.transactions.0.fitid', 'DUPL01');
    }

    public function test_flags_previously_reconciled_fitid(): void
    {
        ReconciledTransaction::create([
            'space_id' => $this->space->id,
            'account_id' => $this->account->id,
            'fitid' => 'ALREADY_REC',
            'amount_cents' => 10000,
            'type' => 'debit',
            'posted_at' => '2026-04-01',
            'memo' => 'Já conciliado',
            'matched_type' => 'ignored',
        ]);

        $ofx = "OFXHEADER:100\n"
            ."<STMTTRN>\n<DTPOSTED>20260401\n<TRNAMT>-100.00\n<FITID>ALREADY_REC\n<MEMO>Tentativa Dupla\n";

        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/parse",
            ['account_id' => $this->account->id, 'ofx_content' => $ofx]
        );

        $response->assertOk()
            ->assertJsonPath('data.transactions.0.already_reconciled', true)
            ->assertJsonPath('data.already_reconciled_count', 1);
    }

    public function test_idor_protection_rejects_account_from_another_space(): void
    {
        $otherUser = User::factory()->create();
        $otherSpace = $otherUser->spaces()->where('kind', Space::PJ)->firstOrFail();
        $otherAccount = $otherSpace->accounts()->create([
            'name' => 'Conta Alheia',
            'type' => 'checking',
            'opening_balance_cents' => 100000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/parse",
            [
                'account_id' => $otherAccount->id,
                'ofx_content' => "OFXHEADER:100\n<STMTTRN>\n<DTPOSTED>20260410\n<TRNAMT>-10.00\n<FITID>F1\n",
            ]
        );

        $response->assertNotFound();
    }

    public function test_reconcile_blocked_when_accounting_period_is_closed(): void
    {
        $this->space->update(['closed_until' => '2026-04-15']);

        $payload = [
            'account_id' => $this->account->id,
            'transactions' => [
                [
                    'fitid' => 'TX_CLOSED_01',
                    'action' => 'ignore',
                    'amount_cents' => 5000,
                    'posted_at' => '2026-04-10', // Data anterior a closed_until
                    'memo' => 'Despesa no período fechado',
                ],
            ],
        ];

        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/reconcile",
            $payload
        );

        $response->assertStatus(422);
    }

    public function test_reconcile_blocked_for_accountant_role_rbac(): void
    {
        $accountant = User::factory()->create();
        $this->space->members()->attach($accountant->id, ['role' => 'contador']);

        Sanctum::actingAs($accountant);

        $payload = [
            'account_id' => $this->account->id,
            'transactions' => [
                [
                    'fitid' => 'TX_ROLE_01',
                    'action' => 'ignore',
                    'amount_cents' => 1000,
                    'posted_at' => '2026-04-20',
                    'memo' => 'Tentativa por contador',
                ],
            ],
        ];

        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/reconcile",
            $payload
        );

        $response->assertForbidden();
    }

    public function test_reconcile_deduplicates_duplicate_fitid_in_same_request_payload(): void
    {
        $category = Category::create([
            'space_id' => $this->space->id,
            'name' => 'Serviços Bancários',
            'type' => 'expense',
        ]);

        $payload = [
            'account_id' => $this->account->id,
            'transactions' => [
                [
                    'fitid' => 'DUPL_IN_PAYLOAD',
                    'action' => 'new_movement',
                    'amount_cents' => 3000,
                    'type' => 'debit',
                    'posted_at' => '2026-04-20',
                    'memo' => 'Tarifa 1',
                    'category_id' => $category->id,
                ],
                [
                    'fitid' => 'DUPL_IN_PAYLOAD',
                    'action' => 'new_movement',
                    'amount_cents' => 3000,
                    'type' => 'debit',
                    'posted_at' => '2026-04-20',
                    'memo' => 'Tarifa 2 Duplicada',
                    'category_id' => $category->id,
                ],
            ],
        ];

        $response = $this->postJson(
            "/api/spaces/{$this->space->id}/ofx/reconcile",
            $payload
        );

        $response->assertOk()
            ->assertJsonPath('data.reconciled_count', 1);

        $count = ReconciledTransaction::query()
            ->where('space_id', $this->space->id)
            ->where('fitid', 'DUPL_IN_PAYLOAD')
            ->count();
        $this->assertSame(1, $count);
    }
}
