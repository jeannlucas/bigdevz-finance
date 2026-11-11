<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\Agreement;
use App\Models\Loan;
use App\Models\PayablePlan;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class LoansTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    private int $accA;

    private int $accB;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->login($this->user);
        $this->accA = $this->account($this->pf, 'Conta Corrente A', '1000.00', '2026-01-01');
        $this->accB = $this->account($this->pf, 'Conta Poupança B', '200.00', '2026-01-01');
    }

    public function test_taken_loan_with_disbursement_credits_account_and_creates_payable_installments(): void
    {
        $response = $this->createLoan($this->pf, [
            'kind' => 'taken',
            'title' => 'Empréstimo Bancário',
            'counterparty' => 'Banco Itaú',
            'principal' => '1000.00',
            'total' => '1200.00',
            'installment_count' => 3,
            'first_due_date' => '2026-03-01',
            'disbursement_account_id' => $this->accA,
            'disbursed_at' => '2026-02-15',
            'notes' => 'Financiamento capital de giro',
        ], 'loan-taken-1');

        $response->assertCreated()
            ->assertJsonPath('data.kind', 'taken')
            ->assertJsonPath('data.title', 'EMPRÉSTIMO BANCÁRIO')
            ->assertJsonPath('data.counterparty', 'BANCO ITAÚ')
            ->assertJsonPath('data.principal', '1000.00')
            ->assertJsonPath('data.total', '1200.00')
            ->assertJsonPath('data.interest', '200.00')
            ->assertJsonPath('data.installment_count', 3)
            ->assertJsonPath('data.remaining', '1200.00')
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.disbursement_account_id', $this->accA)
            ->assertJsonPath('data.disbursed_at', '2026-02-15')
            ->assertJsonPath('data.notes', 'Financiamento capital de giro');

        $loanId = $response->json('data.id');
        $this->assertNotNull($loanId);

        // Saldo creditado pelo principal
        $this->assertBalance($this->accA, '2000.00');

        // Movimentação de desembolso registrada
        $movement = AccountMovement::query()->where('loan_disbursement_id', $loanId)->first();
        $this->assertNotNull($movement);
        $this->assertSame(100000, $movement->amount_cents);
        $this->assertSame($this->accA, $movement->account_id);
        $this->assertSame('2026-02-15', $movement->effective_date->toDateString());

        // Plano de obrigações a pagar gerado
        $loan = Loan::query()->findOrFail($loanId);
        $this->assertNotNull($loan->payable_plan_id);
        $this->assertNull($loan->agreement_id);

        $plan = PayablePlan::query()->findOrFail($loan->payable_plan_id);
        $this->assertSame(120000, $plan->total_cents);
        $this->assertSame(3, $plan->installment_count);
        $this->assertCount(3, $plan->payables);
        $this->assertSame(40000, $plan->payables->first()->amount_cents);
    }

    public function test_granted_loan_with_disbursement_debits_account_and_creates_agreement_installments(): void
    {
        $response = $this->createLoan($this->pf, [
            'kind' => 'granted',
            'title' => 'Mútuo Familiar',
            'counterparty' => 'Carlos Silva',
            'principal' => '500.00',
            'total' => '550.00',
            'installment_count' => 2,
            'first_due_date' => '2026-04-01',
            'disbursement_account_id' => $this->accA,
            'disbursed_at' => '2026-02-15',
            'notes' => 'Auxílio emergencial',
        ], 'loan-granted-1');

        $response->assertCreated()
            ->assertJsonPath('data.kind', 'granted')
            ->assertJsonPath('data.title', 'MÚTUO FAMILIAR')
            ->assertJsonPath('data.counterparty', 'CARLOS SILVA')
            ->assertJsonPath('data.principal', '500.00')
            ->assertJsonPath('data.total', '550.00')
            ->assertJsonPath('data.interest', '50.00')
            ->assertJsonPath('data.installment_count', 2)
            ->assertJsonPath('data.remaining', '550.00')
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.disbursement_account_id', $this->accA)
            ->assertJsonPath('data.disbursed_at', '2026-02-15');

        $loanId = $response->json('data.id');

        // Saldo debitado pelo principal
        $this->assertBalance($this->accA, '500.00');

        // Movimentação de desembolso registrada
        $movement = AccountMovement::query()->where('loan_disbursement_id', $loanId)->first();
        $this->assertNotNull($movement);
        $this->assertSame(-50000, $movement->amount_cents);
        $this->assertSame($this->accA, $movement->account_id);
        $this->assertSame('2026-02-15', $movement->effective_date->toDateString());

        // Acordo a receber gerado
        $loan = Loan::query()->findOrFail($loanId);
        $this->assertNotNull($loan->agreement_id);
        $this->assertNull($loan->payable_plan_id);

        $agreement = Agreement::query()->findOrFail($loan->agreement_id);
        $this->assertSame(55000, $agreement->total_cents);
        $this->assertSame(2, $agreement->installment_count);
        $this->assertCount(2, $agreement->installments);
        $this->assertSame(27500, $agreement->installments->first()->amount_cents);
    }

    public function test_historical_loan_without_disbursement_creates_no_account_movements(): void
    {
        $response = $this->createLoan($this->pf, [
            'kind' => 'taken',
            'title' => 'Financiamento Imobiliário Antigo',
            'counterparty' => 'Banco Santander',
            'principal' => '100000.00',
            'total' => '150000.00',
            'installment_count' => 120,
            'first_due_date' => '2026-05-01',
        ], 'loan-hist-1');

        $response->assertCreated()
            ->assertJsonPath('data.disbursement_account_id', null)
            ->assertJsonPath('data.disbursed_at', null)
            ->assertJsonPath('data.total', '150000.00')
            ->assertJsonPath('data.principal', '100000.00')
            ->assertJsonPath('data.interest', '50000.00');

        $loanId = $response->json('data.id');

        // Contas não movimentadas
        $this->assertBalance($this->accA, '1000.00');
        $this->assertBalance($this->accB, '200.00');
        $this->assertSame(0, AccountMovement::query()->where('loan_disbursement_id', $loanId)->count());
    }

    public function test_loan_validations_total_less_than_principal_and_invalid_installments(): void
    {
        // Total menor que principal
        $this->createLoan($this->pf, [
            'kind' => 'taken',
            'title' => 'Teste Inválido',
            'counterparty' => 'Banco X',
            'principal' => '1000.00',
            'total' => '900.00',
            'installment_count' => 5,
            'first_due_date' => '2026-03-01',
        ], 'loan-inv-1')->assertStatus(422)
            ->assertJsonValidationErrors(['total']);

        // Parcelas inválidas (0)
        $this->createLoan($this->pf, [
            'kind' => 'taken',
            'title' => 'Teste Inválido 2',
            'counterparty' => 'Banco X',
            'principal' => '1000.00',
            'total' => '1000.00',
            'installment_count' => 0,
            'first_due_date' => '2026-03-01',
        ], 'loan-inv-2')->assertStatus(422)
            ->assertJsonValidationErrors(['installment_count']);
    }

    public function test_disbursement_temporal_validations(): void
    {
        // Desembolso antes da abertura da conta
        $this->createLoan($this->pf, [
            'kind' => 'taken',
            'title' => 'Desembolso Passado',
            'counterparty' => 'Banco X',
            'principal' => '1000.00',
            'total' => '1100.00',
            'installment_count' => 5,
            'first_due_date' => '2026-03-01',
            'disbursement_account_id' => $this->accA,
            'disbursed_at' => '2025-12-31', // Abertura foi 2026-01-01
        ], 'loan-temp-1')->assertStatus(422)
            ->assertJsonValidationErrors(['disbursed_at']);

        // Desembolso depois do primeiro vencimento
        $this->createLoan($this->pf, [
            'kind' => 'taken',
            'title' => 'Desembolso Tardio',
            'counterparty' => 'Banco X',
            'principal' => '1000.00',
            'total' => '1100.00',
            'installment_count' => 5,
            'first_due_date' => '2026-03-01',
            'disbursement_account_id' => $this->accA,
            'disbursed_at' => '2026-03-02',
        ], 'loan-temp-2')->assertStatus(422)
            ->assertJsonValidationErrors(['disbursed_at']);
    }

    public function test_loan_cross_space_idor_protection(): void
    {
        $pjAccount = $this->account($this->pj, 'Conta PJ', '5000.00', '2026-01-01');

        // Tentar usar conta do PJ no espaço PF
        $this->createLoan($this->pf, [
            'kind' => 'taken',
            'title' => 'IDOR Test',
            'counterparty' => 'Banco X',
            'principal' => '1000.00',
            'total' => '1200.00',
            'installment_count' => 5,
            'first_due_date' => '2026-03-01',
            'disbursement_account_id' => $pjAccount,
            'disbursed_at' => '2026-02-15',
        ], 'loan-idor-1')->assertStatus(404);
    }

    public function test_loan_idempotency_replay_and_conflict(): void
    {
        $payload = [
            'kind' => 'taken',
            'title' => 'Empréstimo Idempotente',
            'counterparty' => 'Fintech Y',
            'principal' => '2000.00',
            'total' => '2400.00',
            'installment_count' => 4,
            'first_due_date' => '2026-03-01',
            'disbursement_account_id' => $this->accA,
            'disbursed_at' => '2026-02-15',
        ];

        $this->createLoan($this->pf, $payload, 'loan-idemp-1')->assertCreated();
        $this->assertBalance($this->accA, '3000.00');

        // Replay idêntico
        $replay = $this->createLoan($this->pf, $payload, 'loan-idemp-1');
        $replay->assertOk()
            ->assertJsonPath('replayed', true)
            ->assertJsonPath('data.principal', '2000.00')
            ->assertJsonPath('data.total', '2400.00');

        // Saldo não duplica
        $this->assertBalance($this->accA, '3000.00');

        // Payload divergente com a mesma chave gera 409
        $conflictPayload = array_merge($payload, ['total' => '2500.00']);
        $this->createLoan($this->pf, $conflictPayload, 'loan-idemp-1')->assertStatus(409);
    }

    public function test_loan_list_and_show_endpoints(): void
    {
        $this->createLoan($this->pf, [
            'kind' => 'taken',
            'title' => 'Empréstimo 1',
            'counterparty' => 'Banco A',
            'principal' => '1000.00',
            'total' => '1100.00',
            'installment_count' => 2,
            'first_due_date' => '2026-03-01',
        ], 'loan-list-1')->assertCreated();

        $resp2 = $this->createLoan($this->pf, [
            'kind' => 'granted',
            'title' => 'Empréstimo 2',
            'counterparty' => 'Pessoa B',
            'principal' => '500.00',
            'total' => '500.00',
            'installment_count' => 1,
            'first_due_date' => '2026-03-10',
        ], 'loan-list-2');
        $loan2Id = $resp2->json('data.id');

        // List
        $listResponse = $this->withHeader('Authorization', "Bearer {$this->token}")
            ->getJson("/api/spaces/{$this->pf->id}/loans");

        $listResponse->assertOk()
            ->assertJsonCount(2, 'data');

        // Show
        $showResponse = $this->withHeader('Authorization', "Bearer {$this->token}")
            ->getJson("/api/spaces/{$this->pf->id}/loans/{$loan2Id}");

        $showResponse->assertOk()
            ->assertJsonPath('data.id', $loan2Id)
            ->assertJsonPath('data.title', 'EMPRÉSTIMO 2')
            ->assertJsonPath('data.kind', 'granted')
            ->assertJsonPath('data.interest', '0.00')
            ->assertJsonStructure([
                'data' => [
                    'id', 'kind', 'title', 'counterparty', 'principal', 'total', 'interest',
                    'installment_count', 'remaining', 'status', 'first_due_date', 'disbursement_account_id',
                    'disbursed_at', 'notes', 'installments',
                ],
            ]);
    }

    private function createLoan(Space $space, array $payload, string $key): TestResponse
    {
        return $this->withHeaders([
            'Authorization' => "Bearer {$this->token}",
            'Idempotency-Key' => $key,
        ])->postJson("/api/spaces/{$space->id}/loans", $payload);
    }

    private function login(User $user): string
    {
        return $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'password',
            'device_name' => 'teste',
        ])->assertOk()->json('token');
    }

    private function account(Space $space, string $name, string $opening, string $date): int
    {
        return $this->withToken($this->token)->postJson("/api/spaces/{$space->id}/accounts", [
            'name' => $name,
            'opening_balance' => $opening,
            'opening_balance_date' => $date,
        ])->assertCreated()->json('data.id');
    }

    private function assertBalance(int $accountId, string $expected): void
    {
        $this->withToken($this->token)
            ->getJson("/api/spaces/{$this->pf->id}/accounts")
            ->assertOk()
            ->assertJsonPath("data.{$this->accountIndex($accountId)}.balance", $expected);
    }

    private function accountIndex(int $accountId): int
    {
        $accounts = $this->withToken($this->token)
            ->getJson("/api/spaces/{$this->pf->id}/accounts")
            ->json('data');

        foreach ($accounts as $idx => $acc) {
            if ($acc['id'] === $accountId) {
                return $idx;
            }
        }

        $this->fail("Conta {$accountId} não encontrada.");
    }
}
