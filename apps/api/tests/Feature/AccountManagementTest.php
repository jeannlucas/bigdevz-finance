<?php

namespace Tests\Feature;

use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\AccountOpeningAdjustment;
use App\Models\IdempotencyKey;
use App\Models\Receipt;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/** Edição, correção de abertura e arquivamento de contas, em PostgreSQL real de testes. */
class AccountManagementTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    private int $a;

    private int $b;

    /** @var list<int> */
    private array $installments;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->login($this->user);
        $this->a = $this->account($this->pf, 'Conta A', '1000.00', '2026-01-01');
        $this->b = $this->account($this->pf, 'Conta B', '0.00', '2026-01-01');
        $agreement = $this->api('POST', "/api/spaces/{$this->pf->id}/agreements", [
            'description' => 'Venda de veículo', 'total' => '24000.00', 'installment_count' => 12, 'first_due_date' => '2026-02-10',
        ])->assertCreated()->json('data.id');
        $this->installments = array_column($this->api('GET', "/api/spaces/{$this->pf->id}/agreements/{$agreement}")->json('data.installments'), 'id');
    }

    public function test_rename_keeps_identity_space_balance_and_history(): void
    {
        $receipt = $this->receive($this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');

        $this->api('PATCH', $this->url($this->a), ['name' => 'Banco Renomeado'])
            ->assertOk()
            ->assertJsonPath('data.id', $this->a)
            ->assertJsonPath('data.space_id', $this->pf->id)
            ->assertJsonPath('data.name', 'Banco Renomeado')
            ->assertJsonPath('data.balance', '1500.00')
            ->assertJsonPath('data.opening_balance', '1000.00');

        // Campos de abertura e espaço não mudam por aqui.
        $this->api('PATCH', $this->url($this->a), ['name' => 'X', 'space_id' => $this->pj->id, 'opening_balance' => '0.00', 'opening_balance_date' => '2026-01-02'])
            ->assertStatus(422)->assertJsonValidationErrors(['space_id', 'opening_balance', 'opening_balance_date']);
        $this->api('PATCH', $this->url($this->a), ['name' => ''])->assertStatus(422)->assertJsonValidationErrors('name');
        $this->api('PATCH', $this->url($this->a), ['name' => str_repeat('a', 81)])->assertStatus(422);

        $account = Account::query()->findOrFail($this->a);
        $this->assertSame('Banco Renomeado', $account->name);
        $this->assertSame($this->pf->id, $account->space_id);
        $this->assertSame(1, Account::query()->where('space_id', $this->pf->id)->where('name', 'Banco Renomeado')->count(), 'não cria cópia');
        $this->assertSame($this->a, Receipt::query()->findOrFail($receipt)->account_id);
        $this->assertSame(1, AccountMovement::query()->where('account_id', $this->a)->count());
    }

    public function test_other_users_and_spaces_cannot_touch_the_account(): void
    {
        $this->api('PATCH', "/api/spaces/{$this->pj->id}/accounts/{$this->a}", ['name' => 'Pelo PJ'])->assertNotFound();
        $this->api('POST', "/api/spaces/{$this->pj->id}/accounts/{$this->a}/archive")->assertNotFound();

        [$intruder, $intruderPf] = $this->userWithSpaces();
        $this->app['auth']->forgetGuards();
        $other = $this->login($intruder);
        foreach ([$this->pf->id, $intruderPf->id] as $space) {
            $base = "/api/spaces/{$space}/accounts/{$this->a}";
            $this->withToken($other)->patchJson($base, ['name' => 'Alheio'])->assertNotFound();
            $this->withToken($other)->postJson("{$base}/archive")->assertNotFound();
            $this->withToken($other)->postJson("{$base}/opening-adjustment", [
                'opening_balance' => '0.00', 'opening_balance_date' => '2026-01-01', 'reason' => 'Alheio',
            ], ['Idempotency-Key' => "alheio-{$space}"])->assertNotFound();
        }

        $account = Account::query()->findOrFail($this->a);
        $this->assertSame('Conta A', $account->name);
        $this->assertNull($account->archived_at);
        $this->assertSame(100000, $account->opening_balance_cents);
        $this->assertSame(0, IdempotencyKey::query()->where('key', 'like', 'alheio-%')->count());
    }

    public function test_opening_adjustment_without_movements(): void
    {
        $this->adjust($this->b, '250.00', '2025-12-01', 'Saldo do extrato', 'abre-b')
            ->assertCreated()
            ->assertJsonPath('data.account.opening_balance', '250.00')
            ->assertJsonPath('data.account.opening_balance_date', '2025-12-01')
            ->assertJsonPath('data.account.balance', '250.00')
            ->assertJsonPath('data.adjustment.previous_opening_balance', '0.00')
            ->assertJsonPath('data.adjustment.previous_opening_balance_date', '2026-01-01')
            ->assertJsonPath('data.adjustment.reason', 'Saldo do extrato')
            ->assertJsonPath('data.adjustment.user_id', $this->user->id)
            ->assertJsonPath('idempotency.status', 'completed');
        $this->assertNotNull(AccountOpeningAdjustment::query()->where('account_id', $this->b)->sole()->created_at);
        // Sem movimentações, a data pode ir para depois também.
        $this->adjust($this->b, '250.00', '2026-03-01', 'Data do extrato', 'abre-b-2')->assertCreated();
        $this->api('GET', $this->url($this->b))->assertJsonCount(2, 'data.opening_adjustments')
            ->assertJsonPath('data.opening_adjustments.0.new_opening_balance_date', '2026-03-01');
    }

    public function test_opening_adjustment_with_movements_changes_balance_by_the_difference_only(): void
    {
        $receipt = $this->receive($this->a, '500.00', '2026-02-10', 'rec')->json('data.receipt.id');
        $this->reverseAndCorrect($receipt);   // movimentações: +500, -500, +400 (2026-02-10 e 2026-02-12)
        $before = AccountMovement::query()->where('account_id', $this->a)->orderBy('id')->get(['amount_cents', 'effective_date'])->toArray();
        $this->assertBalance($this->a, '1400.00');

        $this->adjust($this->a, '1200.00', '2026-02-10', 'Saldo inicial digitado errado', 'abre')
            ->assertCreated()->assertJsonPath('data.account.balance', '1600.00')->assertJsonPath('data.account.first_movement_date', '2026-02-10');

        $this->assertSame($before, AccountMovement::query()->where('account_id', $this->a)->orderBy('id')->get(['amount_cents', 'effective_date'])->toArray());
        $this->api('GET', "/api/spaces/{$this->pf->id}/summary")
            ->assertJsonPath('data.balance', '1600.00')
            ->assertJsonPath('data.received_total', '400.00');

        // Data depois da primeira movimentação: recusada, nada gravado.
        $this->adjust($this->a, '1200.00', '2026-02-11', 'Data', 'depois')
            ->assertStatus(422)->assertJsonValidationErrors('opening_balance_date')->assertJsonPath('idempotency.status', 'rejected');
        $this->adjust($this->a, '1200.00', '2026-02-10', 'Igual', 'igual')->assertStatus(422)->assertJsonValidationErrors('opening_balance');
        $this->adjust($this->a, '999999999999.99', '2026-02-10', 'Limite', 'limite')->assertStatus(422)->assertJsonValidationErrors('opening_balance');
        $this->adjust($this->a, '-1.00', '2026-02-10', 'Negativo', 'negativo')->assertStatus(422)->assertJsonValidationErrors('opening_balance');
        $this->adjust($this->a, '1300.00', '2026-02-10', '', 'sem-motivo')->assertStatus(422)->assertJsonValidationErrors('reason');

        $account = Account::query()->findOrFail($this->a);
        $this->assertSame(120000, $account->opening_balance_cents);
        $this->assertSame('2026-02-10', $account->opening_balance_date->toDateString());
        $this->assertSame(1, AccountOpeningAdjustment::query()->where('account_id', $this->a)->count());
        // Recebimento novo continua respeitando a abertura.
        $this->receive($this->a, '10.00', '2026-02-09', 'antes-da-abertura')->assertStatus(422)->assertJsonValidationErrors('received_on');
    }

    public function test_lost_response_replays_adjustment_once_and_conflicts_on_other_data(): void
    {
        $first = $this->adjust($this->a, '1100.00', '2026-01-01', 'Ajuste', 'chave')->assertCreated()->json('data.adjustment.id');
        $this->adjust($this->a, '1100.00', '2026-01-01', 'Ajuste', 'chave')
            ->assertOk()->assertJsonPath('data.adjustment.id', $first)->assertJsonPath('data.replayed', true)
            ->assertJsonPath('data.account.balance', '1100.00');
        $this->adjust($this->a, '1200.00', '2026-01-01', 'Ajuste', 'chave')->assertStatus(409);

        $this->assertSame(1, AccountOpeningAdjustment::query()->where('account_id', $this->a)->count());
        $this->assertBalance($this->a, '1100.00');
    }

    public function test_archive_hides_from_new_operations_and_keeps_money_and_history(): void
    {
        $old = $this->receive($this->a, '500.00', '2026-02-10', 'antes-de-arquivar')->assertCreated()->json('data.receipt.id');

        $this->api('POST', $this->url($this->a).'/archive')->assertOk()->assertJsonPath('data.balance', '1500.00');
        $archivedAt = Account::query()->findOrFail($this->a)->archived_at;
        $this->assertNotNull($archivedAt);
        $this->api('POST', $this->url($this->a).'/archive')->assertOk();
        $this->assertEquals($archivedAt, Account::query()->findOrFail($this->a)->archived_at, 'repetir não muda');

        // Lista e consulta histórica continuam.
        $this->api('GET', "/api/spaces/{$this->pf->id}/accounts")->assertJsonCount(2, 'data');
        $this->api('GET', "/api/spaces/{$this->pf->id}/installments/{$this->installments[0]}")->assertJsonPath('data.receipts.0.account_id', $this->a);
        $this->api('GET', "/api/spaces/{$this->pf->id}/summary")
            ->assertJsonPath('data.balance', '1500.00')
            ->assertJsonPath('data.accounts_count', 2)
            ->assertJsonPath('data.active_accounts_count', 1)
            ->assertJsonPath('data.archived_accounts_count', 1);

        // Replay de operação concluída antes do arquivamento: mesmo resultado.
        $this->receive($this->a, '500.00', '2026-02-10', 'antes-de-arquivar')->assertOk()->assertJsonPath('data.receipt.id', $old);
        // Operações novas para a conta arquivada: recusadas e registradas.
        $this->receive($this->a, '100.00', '2026-02-10', 'nova')
            ->assertStatus(422)->assertJsonValidationErrors('account_id')->assertJsonPath('idempotency.status', 'rejected');
        $this->correct($old, $this->a, '400.00', '2026-02-10', 'Valor', 'subst-arquivada')->assertStatus(422)->assertJsonValidationErrors('account_id');
        // Correção da arquivada para uma ativa e estorno continuam possíveis.
        $replacement = $this->correct($old, $this->b, '500.00', '2026-02-10', 'Conta errada', 'para-ativa')->assertCreated()->json('data.replacement.id');
        $this->assertBalance($this->a, '1000.00');
        $this->assertBalance($this->b, '500.00');
        $this->api('POST', $this->url($this->b).'/archive')->assertOk();
        $this->reverse($replacement, 'Não recebido', 'estorno-arquivada')->assertCreated();
        $this->assertBalance($this->b, '0.00');

        // Reativada, volta a receber.
        $this->api('POST', $this->url($this->a).'/unarchive')->assertOk()->assertJsonPath('data.archived_at', null);
        $this->receive($this->a, '100.00', '2026-02-10', 'depois-de-reativar')->assertCreated();
        $this->api('GET', "/api/spaces/{$this->pf->id}/summary")->assertJsonPath('data.active_accounts_count', 1)->assertJsonPath('data.archived_accounts_count', 1);
    }

    /** Item 8: chave que não chegou à API antes do arquivamento. */
    public function test_pending_key_for_archived_account_is_decided_once(): void
    {
        $this->api('POST', $this->url($this->a).'/archive')->assertOk();
        // A tentativa local guardava a chave; ela chega depois do arquivamento.
        $this->receive($this->a, '100.00', '2026-02-10', 'pendente')
            ->assertStatus(422)->assertJsonPath('idempotency.status', 'rejected')->assertJsonPath('idempotency.replayed', false);
        $this->api('POST', $this->url($this->a).'/unarchive')->assertOk();
        // Reativar não reabre a decisão: a mesma chave continua recusada.
        $this->receive($this->a, '100.00', '2026-02-10', 'pendente')
            ->assertStatus(422)->assertJsonPath('idempotency.replayed', true);
        $this->assertSame(0, Receipt::query()->where('idempotency_key', 'pendente')->count());
        $this->assertBalance($this->a, '1000.00');
    }

    private function reverseAndCorrect(int $receipt): void
    {
        $this->correct($receipt, $this->a, '400.00', '2026-02-12', 'Valor e data', 'corrige')->assertCreated();
    }

    private function login(User $user): string
    {
        return $this->postJson('/api/auth/login', ['email' => $user->email, 'password' => 'password', 'device_name' => 'teste'])->json('token');
    }

    private function api(string $method, string $uri, array $data = [], array $headers = []): TestResponse
    {
        return $this->withToken($this->token)->json($method, $uri, $data, $headers);
    }

    private function url(int $account): string
    {
        return "/api/spaces/{$this->pf->id}/accounts/{$account}";
    }

    private function account(Space $space, string $name, string $opening, string $date): int
    {
        return $this->api('POST', "/api/spaces/{$space->id}/accounts", [
            'name' => $name, 'opening_balance' => $opening, 'opening_balance_date' => $date,
        ])->assertCreated()->json('data.id');
    }

    private function adjust(int $account, string $opening, string $date, string $reason, string $key): TestResponse
    {
        return $this->api('POST', $this->url($account).'/opening-adjustment', [
            'opening_balance' => $opening, 'opening_balance_date' => $date, 'reason' => $reason,
        ], ['Idempotency-Key' => $key]);
    }

    private function receive(int $account, string $amount, string $date, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/installments/{$this->installments[0]}/receipts", [
            'account_id' => $account, 'amount' => $amount, 'received_on' => $date,
        ], ['Idempotency-Key' => $key]);
    }

    private function reverse(int $receipt, string $reason, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/receipts/{$receipt}/reversal", ['reason' => $reason], ['Idempotency-Key' => $key]);
    }

    private function correct(int $receipt, int $account, string $amount, string $date, string $reason, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/receipts/{$receipt}/correction", [
            'reason' => $reason, 'account_id' => $account, 'amount' => $amount, 'received_on' => $date,
        ], ['Idempotency-Key' => $key]);
    }

    private function assertBalance(int $account, string $expected): void
    {
        $this->api('GET', $this->url($account))->assertJsonPath('data.balance', $expected);
    }
}
