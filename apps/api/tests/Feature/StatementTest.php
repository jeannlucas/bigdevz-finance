<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\Transfer;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class StatementTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        Sanctum::actingAs($this->user);
    }

    public function test_statement_returns_chronological_movements_with_credit_and_debit_classification(): void
    {
        $account = $this->pf->accounts()->create([
            'name' => 'Nubank Principal',
            'opening_balance_cents' => 100000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $payable = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Assinatura AWS',
            'amount_cents' => 50000,
            'paid_cents' => 50000,
            'due_date' => '2026-02-15',
        ]);

        $payment = Payment::create([
            'space_id' => $this->pf->id,
            'payable_id' => $payable->id,
            'account_id' => $account->id,
            'user_id' => $this->user->id,
            'amount_cents' => 50000,
            'paid_on' => '2026-02-15',
        ]);

        AccountMovement::create([
            'account_id' => $account->id,
            'payment_id' => $payment->id,
            'amount_cents' => -50000,
            'effective_date' => '2026-02-15',
        ]);

        // Entrada de recebimento no dia 10
        $agreement = $this->pf->agreements()->create([
            'description' => 'Venda de Consultoria',
            'total_cents' => 150000,
            'installment_count' => 1,
            'first_due_date' => '2026-02-10',
        ]);

        $installment = $agreement->installments()->create([
            'space_id' => $this->pf->id,
            'number' => 1,
            'amount_cents' => 150000,
            'received_cents' => 150000,
            'due_date' => '2026-02-10',
        ]);

        $receipt = Receipt::create([
            'space_id' => $this->pf->id,
            'installment_id' => $installment->id,
            'account_id' => $account->id,
            'user_id' => $this->user->id,
            'amount_cents' => 150000,
            'received_on' => '2026-02-10',
        ]);

        AccountMovement::create([
            'account_id' => $account->id,
            'receipt_id' => $receipt->id,
            'amount_cents' => 150000,
            'effective_date' => '2026-02-10',
        ]);

        $response = $this->getJson("/api/spaces/{$this->pf->id}/statement");

        $response->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.effective_date', '2026-02-15')
            ->assertJsonPath('data.0.amount', '500.00')
            ->assertJsonPath('data.0.direction', 'debit')
            ->assertJsonPath('data.0.type', 'payment')
            ->assertJsonPath('data.0.description', 'Pagamento: Assinatura AWS')
            ->assertJsonPath('data.1.effective_date', '2026-02-10')
            ->assertJsonPath('data.1.amount', '1500.00')
            ->assertJsonPath('data.1.direction', 'credit')
            ->assertJsonPath('data.1.description', 'Recebimento: Venda de Consultoria');
    }

    public function test_statement_filters_by_account_id(): void
    {
        $account1 = $this->pf->accounts()->create([
            'name' => 'Conta Corrente',
            'opening_balance_cents' => 50000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $account2 = $this->pf->accounts()->create([
            'name' => 'Conta Poupança',
            'opening_balance_cents' => 50000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $payable1 = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Serviço 1',
            'amount_cents' => 10000,
            'paid_cents' => 10000,
            'due_date' => '2026-02-01',
        ]);

        $payment1 = Payment::create([
            'space_id' => $this->pf->id,
            'payable_id' => $payable1->id,
            'account_id' => $account1->id,
            'user_id' => $this->user->id,
            'amount_cents' => 10000,
            'paid_on' => '2026-02-01',
        ]);

        AccountMovement::create([
            'account_id' => $account1->id,
            'payment_id' => $payment1->id,
            'amount_cents' => -10000,
            'effective_date' => '2026-02-01',
        ]);

        $payable2 = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Serviço 2',
            'amount_cents' => 20000,
            'paid_cents' => 20000,
            'due_date' => '2026-02-02',
        ]);

        $payment2 = Payment::create([
            'space_id' => $this->pf->id,
            'payable_id' => $payable2->id,
            'account_id' => $account2->id,
            'user_id' => $this->user->id,
            'amount_cents' => 20000,
            'paid_on' => '2026-02-02',
        ]);

        AccountMovement::create([
            'account_id' => $account2->id,
            'payment_id' => $payment2->id,
            'amount_cents' => -20000,
            'effective_date' => '2026-02-02',
        ]);

        $this->getJson("/api/spaces/{$this->pf->id}/statement?account_id={$account1->id}")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.amount', '100.00');

        $this->getJson("/api/spaces/{$this->pf->id}/statement?account_id={$account2->id}")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.amount', '200.00');
    }

    public function test_statement_protects_against_idor_on_foreign_account(): void
    {
        $pjAccount = $this->pj->accounts()->create([
            'name' => 'PJ Inter',
            'opening_balance_cents' => 50000,
            'opening_balance_date' => '2026-01-01',
        ]);

        // Tentar consultar movimentações de PJ passando o space PF
        $this->getJson("/api/spaces/{$this->pf->id}/statement?account_id={$pjAccount->id}")
            ->assertNotFound();
    }

    public function test_statement_filters_by_date_range_and_direction(): void
    {
        $account = $this->pf->accounts()->create([
            'name' => 'Conta Única',
            'opening_balance_cents' => 100000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $agreement = $this->pf->agreements()->create([
            'description' => 'Contrato 1',
            'total_cents' => 40000,
            'installment_count' => 2,
            'first_due_date' => '2026-02-01',
        ]);

        $inst1 = $agreement->installments()->create([
            'space_id' => $this->pf->id,
            'number' => 1,
            'amount_cents' => 10000,
            'received_cents' => 10000,
            'due_date' => '2026-02-01',
        ]);

        $receipt1 = Receipt::create([
            'space_id' => $this->pf->id,
            'installment_id' => $inst1->id,
            'account_id' => $account->id,
            'user_id' => $this->user->id,
            'amount_cents' => 10000,
            'received_on' => '2026-02-01',
        ]);

        AccountMovement::create([
            'account_id' => $account->id,
            'receipt_id' => $receipt1->id,
            'amount_cents' => 10000,
            'effective_date' => '2026-02-01',
        ]);

        $payable = Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Serviço intermediário',
            'amount_cents' => 20000,
            'paid_cents' => 20000,
            'due_date' => '2026-02-15',
        ]);

        $payment = Payment::create([
            'space_id' => $this->pf->id,
            'payable_id' => $payable->id,
            'account_id' => $account->id,
            'user_id' => $this->user->id,
            'amount_cents' => 20000,
            'paid_on' => '2026-02-15',
        ]);

        AccountMovement::create([
            'account_id' => $account->id,
            'payment_id' => $payment->id,
            'amount_cents' => -20000,
            'effective_date' => '2026-02-15',
        ]);

        $inst2 = $agreement->installments()->create([
            'space_id' => $this->pf->id,
            'number' => 2,
            'amount_cents' => 30000,
            'received_cents' => 30000,
            'due_date' => '2026-02-28',
        ]);

        $receipt2 = Receipt::create([
            'space_id' => $this->pf->id,
            'installment_id' => $inst2->id,
            'account_id' => $account->id,
            'user_id' => $this->user->id,
            'amount_cents' => 30000,
            'received_on' => '2026-02-28',
        ]);

        AccountMovement::create([
            'account_id' => $account->id,
            'receipt_id' => $receipt2->id,
            'amount_cents' => 30000,
            'effective_date' => '2026-02-28',
        ]);

        // Filtrando intervalo
        $this->getJson("/api/spaces/{$this->pf->id}/statement?from=2026-02-10&to=2026-02-20")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.amount', '200.00');

        // Filtrando direção: somente crédito
        $this->getJson("/api/spaces/{$this->pf->id}/statement?direction=credit")
            ->assertOk()
            ->assertJsonCount(2, 'data');

        // Filtrando direção: somente débito
        $this->getJson("/api/spaces/{$this->pf->id}/statement?direction=debit")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.amount', '200.00');
    }

    public function test_statement_handles_transfer_movements_with_correct_labels(): void
    {
        $origin = $this->pf->accounts()->create([
            'name' => 'Origem Itaú',
            'opening_balance_cents' => 100000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $dest = $this->pf->accounts()->create([
            'name' => 'Destino Nubank',
            'opening_balance_cents' => 50000,
            'opening_balance_date' => '2026-01-01',
        ]);

        $transfer = Transfer::create([
            'space_id' => $this->pf->id,
            'user_id' => $this->user->id,
            'source_account_id' => $origin->id,
            'destination_account_id' => $dest->id,
            'amount_cents' => 30000,
            'transferred_at' => '2026-02-10',
            'notes' => 'Aporte mensal',
        ]);

        AccountMovement::create([
            'account_id' => $origin->id,
            'transfer_id' => $transfer->id,
            'amount_cents' => -30000,
            'effective_date' => '2026-02-10',
        ]);

        AccountMovement::create([
            'account_id' => $dest->id,
            'transfer_id' => $transfer->id,
            'amount_cents' => 30000,
            'effective_date' => '2026-02-10',
        ]);

        $this->getJson("/api/spaces/{$this->pf->id}/statement?account_id={$origin->id}")
            ->assertOk()
            ->assertJsonPath('data.0.direction', 'debit')
            ->assertJsonPath('data.0.description', 'Transferência para Destino Nubank');

        $this->getJson("/api/spaces/{$this->pf->id}/statement?account_id={$dest->id}")
            ->assertOk()
            ->assertJsonPath('data.0.direction', 'credit')
            ->assertJsonPath('data.0.description', 'Transferência de Origem Itaú');
    }
}
