<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Agreement;
use App\Models\Installment;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use RuntimeException;
use Tests\TestCase;

class IsolationAndAtomicityTest extends TestCase
{
    use DatabaseTransactions;

    private Space $pf;

    private Space $pj;

    private Account $pfAccount;

    private Account $pjAccount;

    private Installment $installment;

    protected function setUp(): void
    {
        parent::setUp();
        [$user, $this->pf, $this->pj] = $this->userWithSpaces();
        Sanctum::actingAs($user);

        $this->pfAccount = Account::query()->findOrFail($this->postJson("/api/spaces/{$this->pf->id}/accounts", [
            'name' => 'PF', 'opening_balance' => '1000.00', 'opening_balance_date' => '2026-01-01',
        ])->assertCreated()->json('data.id'));
        $this->pjAccount = Account::query()->findOrFail($this->postJson("/api/spaces/{$this->pj->id}/accounts", [
            'name' => 'PJ', 'opening_balance' => '0.00', 'opening_balance_date' => '2026-01-01',
        ])->assertCreated()->json('data.id'));
        $agreement = Agreement::query()->findOrFail($this->postJson("/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Venda de veículo', 'total' => '24000.00', 'installment_count' => 12, 'first_due_date' => '2026-02-10',
        ])->assertCreated()->json('data.id'));
        $this->installment = $agreement->installments()->orderBy('number')->firstOrFail();
    }

    /** Cenário 5. */
    public function test_pj_account_cannot_receive_pf_installment(): void
    {
        $this->postJson("/api/spaces/{$this->pf->id}/installments/{$this->installment->id}/receipts", [
            'account_id' => $this->pjAccount->id, 'amount' => '2000.00', 'received_on' => '2026-02-10',
        ], ['Idempotency-Key' => 'pj-em-pf'])->assertStatus(422)->assertJsonValidationErrors('account_id');

        // Usar o espaço PJ na rota também não alcança a parcela PF.
        $this->postJson("/api/spaces/{$this->pj->id}/installments/{$this->installment->id}/receipts", [
            'account_id' => $this->pjAccount->id, 'amount' => '2000.00', 'received_on' => '2026-02-10',
        ], ['Idempotency-Key' => 'pj-rota'])->assertNotFound();

        $this->assertNothingWritten();
    }

    /** Cenário 6. */
    public function test_other_user_cannot_reach_resources_by_changing_ids(): void
    {
        $this->postJson("/api/spaces/{$this->pf->id}/installments/{$this->installment->id}/receipts", [
            'account_id' => $this->pfAccount->id, 'amount' => '100.00', 'received_on' => '2026-02-10',
        ], ['Idempotency-Key' => 'dono'])->assertCreated();
        $receiptCount = Receipt::query()->where('space_id', $this->pf->id)->count();

        $intruder = User::factory()->create();
        Sanctum::actingAs($intruder);
        $ownSpace = $intruder->spaces()->where('kind', 'PF')->firstOrFail();
        $ownAccount = $this->postJson("/api/spaces/{$ownSpace->id}/accounts", [
            'name' => 'Minha', 'opening_balance' => '0.00', 'opening_balance_date' => '2026-01-01',
        ])->assertCreated()->json('data.id');
        $agreementId = $this->installment->agreement_id;

        foreach ([
            "/api/spaces/{$this->pf->id}/summary",
            "/api/spaces/{$this->pf->id}/accounts",
            "/api/spaces/{$this->pf->id}/accounts/{$this->pfAccount->id}",
            "/api/spaces/{$this->pf->id}/agreements",
            "/api/spaces/{$this->pf->id}/agreements/{$agreementId}",
            "/api/spaces/{$this->pf->id}/installments/{$this->installment->id}",
            "/api/spaces/{$ownSpace->id}/accounts/{$this->pfAccount->id}",
            "/api/spaces/{$ownSpace->id}/agreements/{$agreementId}",
            "/api/spaces/{$ownSpace->id}/installments/{$this->installment->id}",
        ] as $uri) {
            $this->getJson($uri)->assertNotFound()->assertJsonMissingPath('data');
        }

        // Escrita com IDs alheios: espaço alheio, parcela alheia ou conta alheia.
        $this->postJson("/api/spaces/{$this->pf->id}/accounts", ['name' => 'X', 'opening_balance' => '1.00', 'opening_balance_date' => '2026-01-01'])->assertNotFound();
        $this->postJson("/api/spaces/{$this->pf->id}/installments/{$this->installment->id}/receipts", [
            'account_id' => $this->pfAccount->id, 'amount' => '100.00', 'received_on' => '2026-02-10',
        ], ['Idempotency-Key' => 'dono'])->assertNotFound();
        $this->postJson("/api/spaces/{$ownSpace->id}/installments/{$this->installment->id}/receipts", [
            'account_id' => $ownAccount, 'amount' => '100.00', 'received_on' => '2026-02-10',
        ], ['Idempotency-Key' => 'x1'])->assertNotFound();

        $ownAgreement = $this->postJson("/api/spaces/{$ownSpace->id}/agreements", [
            'description' => 'Própria', 'total' => '10.00', 'installment_count' => 1, 'first_due_date' => '2026-02-10',
        ])->assertCreated()->json('data.installments.0.id');
        $this->postJson("/api/spaces/{$ownSpace->id}/installments/{$ownAgreement}/receipts", [
            'account_id' => $this->pfAccount->id, 'amount' => '10.00', 'received_on' => '2026-02-10',
        ], ['Idempotency-Key' => 'x2'])->assertStatus(422)->assertJsonValidationErrors('account_id')
            ->assertJsonMissing(['name' => 'PF']);

        $this->assertSame($receiptCount, Receipt::query()->where('space_id', $this->pf->id)->count());
        $this->assertSame(0, Receipt::query()->where('space_id', $ownSpace->id)->count());
        $this->assertSame(0, $this->installment->agreement->installments()->where('number', 2)->value('received_cents'));
        $this->assertSame(110000, $this->pfAccount->fresh()->balanceCents());
    }

    public function test_non_numeric_or_huge_ids_return_not_found(): void
    {
        $this->getJson('/api/spaces/abc/accounts')->assertNotFound();
        $this->getJson('/api/spaces/99999999999999999999999/accounts')->assertNotFound();
        $this->getJson("/api/spaces/{$this->pf->id}/installments/1e3")->assertNotFound();
    }

    /** Cenário 7: falha entre o recebimento e a movimentação. */
    public function test_failure_while_recording_rolls_back_everything(): void
    {
        AccountMovement::creating(static fn () => throw new RuntimeException('falha simulada na movimentação'));

        $this->withoutExceptionHandling();
        try {
            $this->postJson("/api/spaces/{$this->pf->id}/installments/{$this->installment->id}/receipts", [
                'account_id' => $this->pfAccount->id, 'amount' => '2000.00', 'received_on' => '2026-02-10',
            ], ['Idempotency-Key' => 'falha']);
            $this->fail('A falha simulada deveria interromper o recebimento.');
        } catch (RuntimeException $error) {
            $this->assertSame('falha simulada na movimentação', $error->getMessage());
        } finally {
            AccountMovement::flushEventListeners();
        }

        $this->assertNothingWritten();

        // A mesma chave pode ser reutilizada depois da falha.
        $this->postJson("/api/spaces/{$this->pf->id}/installments/{$this->installment->id}/receipts", [
            'account_id' => $this->pfAccount->id, 'amount' => '2000.00', 'received_on' => '2026-02-10',
        ], ['Idempotency-Key' => 'falha'])->assertCreated()->assertJsonPath('data.account.balance', '3000.00');
    }

    private function assertNothingWritten(): void
    {
        $this->assertSame(0, Receipt::query()->whereIn('space_id', [$this->pf->id, $this->pj->id])->count());
        $this->assertSame(0, AccountMovement::query()->whereIn('account_id', [$this->pfAccount->id, $this->pjAccount->id])->count());
        $this->assertSame(0, $this->installment->fresh()->received_cents);
        $this->assertSame(100000, $this->pfAccount->fresh()->balanceCents());
        $this->assertSame(0, $this->pjAccount->fresh()->balanceCents());
    }
}
