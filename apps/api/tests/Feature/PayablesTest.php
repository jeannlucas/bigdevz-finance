<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\IdempotencyKey;
use App\Models\ObligationChange;
use App\Models\Payable;
use App\Models\Payment;
use App\Models\PaymentReversal;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Testing\TestResponse;
use RuntimeException;
use Tests\TestCase;

/** A pagar em PostgreSQL real de testes. "Hoje" fixo em 15/03/2026 (America/Sao_Paulo). */
class PayablesTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    private int $a;

    private int $b;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-03-15 12:00:00', 'America/Sao_Paulo'));
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->postJson('/api/auth/login', ['email' => $this->user->email, 'password' => 'password', 'device_name' => 't'])->json('token');
        $this->a = $this->account($this->pf, 'Conta A', '1000.00', '2026-01-01');
        $this->b = $this->account($this->pf, 'Conta B', '50.00', '2026-01-01');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_single_payable_edit_and_cancel_never_touch_balance(): void
    {
        $id = $this->create(['kind' => 'single', 'description' => 'Conserto', 'payee' => 'Oficina', 'amount' => '300.00', 'due_date' => '2026-03-20'], 'cria')
            ->assertCreated()->assertJsonPath('data.payables.0.status', 'open')->assertJsonPath('data.payables.0.remaining', '300.00')
            ->json('data.payables.0.id');
        $this->create(['kind' => 'single', 'description' => 'Conserto', 'payee' => 'Oficina', 'amount' => '300.00', 'due_date' => '2026-03-20'], 'cria')
            ->assertOk()->assertJsonPath('data.payables.0.id', $id);
        $this->create(['kind' => 'single', 'description' => 'Outro', 'amount' => '1.00', 'due_date' => '2026-03-20'], 'cria')->assertStatus(409);
        $this->assertBalance($this->a, '1000.00');
        $this->summary()->assertJsonPath('data.payables.open_total', '300.00')->assertJsonPath('data.balance', '1050.00');

        $this->api('PATCH', $this->payableUrl($id), ['amount' => '350.00', 'description' => 'Conserto do carro', 'reason' => 'Orçamento novo'])
            ->assertOk()->assertJsonPath('data.amount', '350.00')->assertJsonPath('changes.0.action', 'edit')
            ->assertJsonPath('changes.0.before.amount_cents', 30000)->assertJsonPath('changes.0.reason', 'Orçamento novo');
        $payment = $this->pay($id, $this->a, '100.00', '2026-03-10', 'paga')->assertCreated()->json('data.payment.id');
        $this->api('PATCH', $this->payableUrl($id), ['amount' => '99.99'])->assertStatus(422)->assertJsonValidationErrors('amount');
        $this->api('POST', $this->payableUrl($id).'/cancel', ['reason' => 'Desisti'])->assertStatus(422)->assertJsonValidationErrors('payable');

        $this->reverse($payment, 'Pago por engano', 'estorna')->assertCreated();
        $this->api('POST', $this->payableUrl($id).'/cancel', ['reason' => 'Desisti'])
            ->assertOk()->assertJsonPath('data.status', 'cancelled')->assertJsonPath('data.cancel_reason', 'Desisti');
        $this->api('PATCH', $this->payableUrl($id), ['amount' => '10.00'])->assertStatus(422);
        $this->pay($id, $this->a, '10.00', '2026-03-10', 'cancelada')->assertStatus(422)->assertJsonValidationErrors('payable');
        $this->assertBalance($this->a, '1000.00');
        $this->summary()->assertJsonPath('data.payables.open_total', '0.00')->assertJsonPath('data.payables.paid_total', '0.00');
        $this->assertSame(2, ObligationChange::query()->where('subject', 'payable')->where('subject_id', $id)->count());
    }

    public function test_installment_schedule_is_exact_previewed_and_unique(): void
    {
        $this->api('POST', "/api/spaces/{$this->pf->id}/payables/preview", ['total' => '100.00', 'installment_count' => 3, 'first_due_date' => '2028-01-31'])
            ->assertOk()->assertJsonPath('data.*.amount', ['33.34', '33.33', '33.33'])
            ->assertJsonPath('data.*.due_date', ['2028-01-31', '2028-02-29', '2028-03-31']);
        $this->assertSame(0, Payable::query()->where('space_id', $this->pf->id)->count(), 'prévia não grava');

        $body = ['kind' => 'installment', 'description' => 'Notebook', 'total' => '100.00', 'installment_count' => 3, 'first_due_date' => '2026-01-31'];
        $this->create($body, 'parcela')->assertCreated()
            ->assertJsonPath('data.payables.*.due_date', ['2026-01-31', '2026-02-28', '2026-03-31'])
            ->assertJsonPath('data.payables.*.plan.installment_number', [1, 2, 3]);
        $this->create($body, 'parcela')->assertOk()->assertJsonPath('data.replayed', true);
        $this->assertSame(3, Payable::query()->where('space_id', $this->pf->id)->count());
        $this->assertSame(10000, (int) Payable::query()->where('space_id', $this->pf->id)->sum('amount_cents'));
        $this->create(['kind' => 'installment', 'description' => 'X', 'total' => '0.02', 'installment_count' => 3, 'first_due_date' => '2026-01-31'], 'invalida')
            ->assertStatus(422)->assertJsonValidationErrors('installment_count')->assertJsonPath('idempotency.status', 'rejected');
    }

    public function test_recurrence_generation_edit_and_end_preserve_history(): void
    {
        $recurrence = $this->create(['kind' => 'recurring', 'description' => 'Aluguel', 'payee' => 'Imobiliária', 'amount' => '1500.00', 'start_date' => '2026-01-31', 'approved_until' => '2027-03-01', 'confirm_past' => true], 'aluguel')
            ->assertCreated()->assertJsonPath('data.recurrence.reference_day', 31)->json('data.recurrence.id');
        $occurrences = fn () => Payable::query()->where('recurrence_id', $recurrence)->orderBy('cycle');
        // Jan/2026 até o horizonte (mar/2027): 15 ciclos, dia 31 ajustado.
        $this->assertSame(15, $occurrences()->count());
        $this->assertSame(['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'], $occurrences()->limit(4)->pluck('due_date')->map->toDateString()->all());
        $this->assertSame('2027-03-31', $occurrences()->get()->last()->due_date->toDateString());

        Artisan::call('payables:generate');
        Artisan::call('payables:generate');
        $this->assertSame(15, $occurrences()->count(), 'repetir não duplica');

        [$jan, $feb, $mar, $apr, $may] = $occurrences()->limit(5)->pluck('id')->all();
        $this->pay($jan, $this->a, '1500.00', '2026-02-01', 'jan')->assertCreated();
        $this->pay($apr, $this->a, '100.00', '2026-03-10', 'abr-parcial')->assertCreated();
        $this->api('PATCH', $this->payableUrl($may), ['amount' => '1400.00'])->assertOk();
        $this->api('POST', $this->payableUrl($mar).'/cancel', ['reason' => 'Mês isento'])->assertOk();

        // Futuras: só as de hoje em diante, sem pagamento, não editadas nem canceladas.
        $this->api('PATCH', "/api/spaces/{$this->pf->id}/recurrences/{$recurrence}", ['amount' => '1600.00'])->assertOk();
        $amounts = Payable::query()->whereIn('id', [$jan, $feb, $mar, $apr, $may])->orderBy('cycle')->pluck('amount_cents')->all();
        $this->assertSame([150000, 150000, 150000, 150000, 140000], $amounts, 'passadas, canceladas, parciais e editadas ficam');
        $this->assertSame(160000, $occurrences()->where('cycle', '2026-06-01')->value('amount_cents'));

        Carbon::setTestNow(Carbon::parse('2026-04-15 12:00:00', 'America/Sao_Paulo'));
        Artisan::call('payables:generate');
        $this->assertSame(16, $occurrences()->count(), 'novo ciclo no horizonte');
        $this->assertNotNull(Payable::query()->findOrFail($mar)->cancelled_at, 'cancelada não volta');

        // Encerrar em 31/05: cancela as seguintes sem pagamento, mantém as demais.
        $this->pay($occurrences()->where('cycle', '2026-07-01')->value('id'), $this->a, '10.00', '2026-04-10', 'jul-parcial')->assertCreated();
        $this->api('POST', "/api/spaces/{$this->pf->id}/recurrences/{$recurrence}/end", ['end_date' => '2026-05-31', 'reason' => 'Mudança'])
            ->assertOk()->assertJsonPath('data.end_date', '2026-05-31');
        $this->assertSame(['2026-06-01'], $occurrences()->where('cycle', '>', '2026-05-01')->whereNull('cancelled_at')->where('paid_cents', 0)->pluck('cycle')->map->toDateString()->all() === [] ? ['2026-06-01'] : ['erro']);
        $this->assertSame(1, $occurrences()->where('cycle', '>', '2026-05-01')->whereNull('cancelled_at')->count(), 'só a parcialmente paga continua');
        Carbon::setTestNow(Carbon::parse('2026-06-15 12:00:00', 'America/Sao_Paulo'));
        Artisan::call('payables:generate');
        $this->assertSame(16, $occurrences()->count(), 'encerrada não gera');
        $this->assertSame(150000, Payment::query()->where('payable_id', $jan)->value('amount_cents'), 'pagamento preservado');
    }

    public function test_card_bills_wait_for_total_and_stop_when_archived(): void
    {
        $card = $this->api('POST', "/api/spaces/{$this->pf->id}/cards", ['name' => 'Cartão Azul', 'due_day' => 31])->assertCreated()->json('data.id');
        $bills = fn () => Payable::query()->where('card_id', $card)->orderBy('cycle');
        // Mar/2026 (mês atual) até mar/2027.
        $this->assertSame(13, $bills()->count());
        $this->assertSame(['2026-03-31', '2026-04-30'], $bills()->limit(2)->pluck('due_date')->map->toDateString()->all());
        $march = $bills()->value('id');
        $this->api('GET', $this->payableUrl($march))->assertJsonPath('data.status', 'awaiting_amount')
            ->assertJsonPath('data.amount', null)->assertJsonPath('data.remaining', null)->assertJsonPath('data.overdue', false);
        $this->summary()->assertJsonPath('data.payables.awaiting_amount_count', 13)->assertJsonPath('data.payables.open_total', '0.00');

        $this->pay($march, $this->a, '10.00', '2026-03-10', 'sem-total')->assertStatus(422)->assertJsonValidationErrors('payable');
        $this->api('PATCH', $this->payableUrl($march), ['amount' => '1200.00'])->assertOk()->assertJsonPath('data.status', 'open');
        $this->pay($march, $this->a, '200.00', '2026-03-10', 'parcial')->assertCreated();
        $this->api('PATCH', $this->payableUrl($march), ['amount' => '150.00'])->assertStatus(422);
        $this->api('PATCH', $this->payableUrl($march), ['amount' => null])->assertStatus(422);
        // A fatura é a própria obrigação: conta uma vez.
        $this->summary()->assertJsonPath('data.payables.open_total', '1000.00')->assertJsonPath('data.payables.awaiting_amount_count', 12);
        $this->assertSame(0, $bills()->where('id', '<>', $march)->whereNotNull('amount_cents')->count(), 'não copia o valor');

        $this->api('POST', "/api/spaces/{$this->pf->id}/cards/{$card}/archive")->assertOk();
        Carbon::setTestNow(Carbon::parse('2026-05-15 12:00:00', 'America/Sao_Paulo'));
        Artisan::call('payables:generate');
        $this->assertSame(13, $bills()->count(), 'arquivado não gera');
        $this->pay($march, $this->a, '1000.00', '2026-03-12', 'quita')->assertCreated()->assertJsonPath('data.payable.status', 'paid');
    }

    public function test_payment_flow_balance_remaining_and_negative_policy(): void
    {
        $id = $this->single('300.00');
        $this->pay($id, $this->a, '100.00', '2026-03-10', 'p1')->assertCreated()
            ->assertJsonPath('data.account.balance', '900.00')->assertJsonPath('data.payable.remaining', '200.00')->assertJsonPath('data.payable.status', 'partial');
        $this->pay($id, $this->a, '200.01', '2026-03-10', 'acima')->assertStatus(422)->assertJsonValidationErrors('amount');
        $this->pay($id, $this->a, '200.00', '2026-03-10', 'p2')->assertCreated()
            ->assertJsonPath('data.account.balance', '700.00')->assertJsonPath('data.payable.status', 'paid');
        $movement = AccountMovement::query()->where('payment_id', Payment::query()->where('payable_id', $id)->orderBy('id')->value('id'))->sole();
        $this->assertSame(-10000, $movement->amount_cents);

        // Sem limite de saldo: a conta pode ficar negativa.
        $bill = $this->single('300.00');
        $this->pay($bill, $this->b, '300.00', '2026-03-10', 'negativo')->assertCreated()->assertJsonPath('data.account.balance', '-250.00');
        // Conta obrigatória, ativa, data válida.
        $other = $this->single('10.00');
        $this->api('POST', $this->payableUrl($other).'/payments', ['amount' => '1.00', 'paid_on' => '2026-03-10'], ['Idempotency-Key' => 'sem-conta'])
            ->assertStatus(422)->assertJsonValidationErrors('account_id');
        $this->pay($other, $this->a, '1.00', '2025-12-31', 'antes')->assertStatus(422)->assertJsonValidationErrors('paid_on');
        $this->pay($other, $this->a, '1.00', '2026-03-16', 'futuro')->assertStatus(422)->assertJsonValidationErrors('paid_on');
        $this->api('POST', "/api/spaces/{$this->pf->id}/accounts/{$this->b}/archive")->assertOk();
        $this->pay($other, $this->b, '1.00', '2026-03-10', 'arquivada')->assertStatus(422)->assertJsonValidationErrors('account_id');
        $this->summary()->assertJsonPath('data.balance', '450.00')->assertJsonPath('data.payables.paid_total', '600.00');
    }

    public function test_reversal_and_correction_keep_chain_and_net_effects(): void
    {
        $id = $this->single('300.00');
        $payment = $this->pay($id, $this->a, '100.00', '2026-03-10', 'p')->json('data.payment.id');

        $this->reverse($payment, 'Débito duplicado', 'e1')->assertCreated()
            ->assertJsonPath('data.original.status', 'reversed')->assertJsonPath('data.payable.remaining', '300.00')
            ->assertJsonPath('data.accounts.0.balance', '1000.00');
        $reversal = PaymentReversal::query()->where('payment_id', $payment)->sole();
        $this->assertSame(10000, $reversal->movement->amount_cents);
        $this->assertSame('2026-03-10', $reversal->movement->effective_date->toDateString());
        $this->assertSame(10000, Payment::query()->findOrFail($payment)->amount_cents, 'original preservado');
        $this->reverse($payment, 'Débito duplicado', 'e1')->assertOk()->assertJsonPath('data.replayed', true);
        $this->reverse($payment, 'De novo', 'e2')->assertStatus(422)->assertJsonValidationErrors('payment');
        $this->pay($id, $this->a, '100.00', '2026-03-10', 'p')->assertOk()->assertJsonPath('data.payment.status', 'reversed')
            ->assertJsonPath('data.account.balance', '1000.00');

        // Correção: conta e valor; cadeia preservada.
        $second = $this->pay($id, $this->a, '120.00', '2026-03-11', 'p2')->json('data.payment.id');
        $replacement = $this->correct($second, $this->b, '80.00', '2026-03-12', 'Conta e valor errados', 'c1')->assertCreated()
            ->assertJsonPath('data.replacement.replaces_payment_id', $second)->assertJsonPath('data.payable.remaining', '220.00')
            ->json('data.replacement.id');
        $this->assertBalance($this->a, '1000.00');
        $this->assertBalance($this->b, '-30.00');
        $this->correct($second, $this->a, '70.00', '2026-03-12', 'De novo', 'c2')->assertStatus(422)->assertJsonValidationErrors('payment');
        $this->correct($replacement, $this->b, '80.00', '2026-03-12', 'Nada', 'igual')->assertStatus(422)->assertJsonValidationErrors('payment');
        $this->correct($replacement, $this->b, '80.00', '2025-12-31', 'Antes', 'antes')->assertStatus(422)->assertJsonValidationErrors('paid_on');

        // Conta arquivada: estorno sai dela; substituto não entra nela.
        $this->api('POST', "/api/spaces/{$this->pf->id}/accounts/{$this->b}/archive")->assertOk();
        $this->correct($replacement, $this->b, '90.00', '2026-03-12', 'Valor', 'para-arquivada')->assertStatus(422)->assertJsonValidationErrors('account_id');
        $this->correct($replacement, $this->a, '80.00', '2026-03-12', 'Conta', 'para-ativa')->assertCreated();
        $this->assertBalance($this->b, '50.00');
        $this->assertBalance($this->a, '920.00');
        $this->summary()->assertJsonPath('data.payables.paid_total', '80.00')->assertJsonPath('data.balance', '970.00');
        $this->api('GET', $this->payableUrl($id))->assertJsonCount(4, 'data.payments');
    }

    public function test_failure_inside_payment_correction_rolls_back(): void
    {
        $id = $this->single('300.00');
        $payment = $this->pay($id, $this->a, '100.00', '2026-03-10', 'p')->json('data.payment.id');
        Payment::creating(static fn () => throw new RuntimeException('falha simulada'));
        $this->withoutExceptionHandling();
        try {
            $this->correct($payment, $this->a, '90.00', '2026-03-10', 'Valor', 'falha');
            $this->fail('deveria falhar');
        } catch (RuntimeException) {
        } finally {
            Payment::flushEventListeners();
        }
        $this->assertSame(0, PaymentReversal::query()->where('payable_id', $id)->count());
        $this->assertSame(10000, Payable::query()->findOrFail($id)->paid_cents);
        $this->assertBalance($this->a, '900.00');
        $this->assertSame(0, IdempotencyKey::query()->where('key', 'falha')->count());
        $this->correct($payment, $this->a, '90.00', '2026-03-10', 'Valor', 'falha')->assertCreated();
        $this->assertBalance($this->a, '910.00');
    }

    public function test_rejected_payment_key_stays_rejected_after_conditions_change(): void
    {
        $id = $this->single('100.00');
        $paid = $this->pay($id, $this->a, '100.00', '2026-03-10', 'quita')->json('data.payment.id');
        $this->pay($id, $this->a, '50.00', '2026-03-10', 'recusada')->assertStatus(422)->assertJsonPath('idempotency.status', 'rejected');

        $this->reverse($paid, 'Não pago', 'reabre')->assertCreated();
        $this->api('PATCH', $this->payableUrl($id), ['amount' => '500.00'])->assertOk();
        $this->pay($id, $this->a, '50.00', '2026-03-10', 'recusada')->assertStatus(422)->assertJsonPath('idempotency.replayed', true);
        $this->assertSame(0, Payment::query()->where('payable_id', $id)->where('amount_cents', 5000)->count());
        $this->pay($id, $this->a, '50.00', '2026-03-10', 'nova')->assertCreated();
    }

    public function test_other_users_and_spaces_cannot_reach_payables(): void
    {
        $id = $this->single('300.00');
        $payment = $this->pay($id, $this->a, '100.00', '2026-03-10', 'p')->json('data.payment.id');
        $recurrence = $this->create(['kind' => 'recurring', 'description' => 'Luz', 'amount' => '90.00', 'start_date' => '2026-03-10', 'approved_until' => '2027-03-01', 'confirm_past' => true], 'luz')->json('data.recurrence.id');
        $card = $this->api('POST', "/api/spaces/{$this->pf->id}/cards", ['name' => 'Cartão', 'due_day' => 10])->json('data.id');
        $pjAccount = $this->account($this->pj, 'PJ', '0.00', '2026-01-01');
        $this->pay($id, $pjAccount, '1.00', '2026-03-10', 'conta-pj')->assertStatus(422)->assertJsonValidationErrors('account_id');

        [$intruder, $intruderPf] = $this->userWithSpaces();
        $this->app['auth']->forgetGuards();
        $other = $this->postJson('/api/auth/login', ['email' => $intruder->email, 'password' => 'password', 'device_name' => 't'])->json('token');
        $key = 0;
        foreach ([$this->pf->id, $intruderPf->id, $this->pj->id] as $space) {
            $token = $space === $this->pj->id ? $this->token : $other;
            $base = "/api/spaces/{$space}";
            $this->withToken($token)->getJson("{$base}/payables/{$id}")->assertNotFound();
            $this->withToken($token)->patchJson("{$base}/payables/{$id}", ['amount' => '1.00'])->assertNotFound();
            $this->withToken($token)->postJson("{$base}/payables/{$id}/cancel", ['reason' => 'Alheio'])->assertNotFound();
            $this->withToken($token)->postJson("{$base}/payables/{$id}/payments", ['account_id' => $this->a, 'amount' => '1.00', 'paid_on' => '2026-03-10'], ['Idempotency-Key' => 'idor-'.$key++])->assertNotFound();
            $this->withToken($token)->postJson("{$base}/payments/{$payment}/reversal", ['reason' => 'Alheio'], ['Idempotency-Key' => 'idor-'.$key++])->assertNotFound();
            $this->withToken($token)->postJson("{$base}/payments/{$payment}/correction", ['reason' => 'Alheio', 'account_id' => $this->a, 'amount' => '1.00', 'paid_on' => '2026-03-10'], ['Idempotency-Key' => 'idor-'.$key++])->assertNotFound();
            $this->withToken($token)->patchJson("{$base}/recurrences/{$recurrence}", ['amount' => '1.00'])->assertNotFound();
            $this->withToken($token)->postJson("{$base}/recurrences/{$recurrence}/end")->assertNotFound();
            $this->withToken($token)->postJson("{$base}/cards/{$card}/archive")->assertNotFound();
        }
        $this->withToken($other)->getJson("/api/spaces/{$intruderPf->id}/payables")->assertOk()->assertJsonCount(0, 'data');
        $this->app['auth']->forgetGuards();
        $this->api('GET', "/api/spaces/{$this->pj->id}/payables")->assertOk()->assertJsonCount(0, 'data');
        $this->assertSame(0, IdempotencyKey::query()->where('key', 'like', 'idor-%')->count());
        $this->assertSame(10000, Payable::query()->findOrFail($id)->paid_cents);
    }

    public function test_summary_separates_overdue_upcoming_and_awaiting(): void
    {
        $this->single('100.00', '2026-03-01');   // vencida
        $partial = $this->single('200.00', '2026-03-10');   // vencida e parcial
        $this->pay($partial, $this->a, '50.00', '2026-03-10', 'parcial')->assertCreated();
        $this->single('300.00', '2026-04-14');   // em 30 dias
        $this->single('400.00', '2026-04-15');   // fora dos 30 dias
        $this->api('GET', $this->payableUrl($partial))->assertJsonPath('data.status', 'partial')->assertJsonPath('data.overdue', true);

        $this->summary()
            ->assertJsonPath('data.payables.open_total', '950.00')
            ->assertJsonPath('data.payables.overdue_total', '250.00')
            ->assertJsonPath('data.payables.overdue_count', 2)
            ->assertJsonPath('data.payables.due_next_30_days_total', '300.00')
            ->assertJsonPath('data.payables.paid_total', '50.00')
            ->assertJsonPath('data.payables.today', '2026-03-15')
            ->assertJsonPath('data.balance', '1000.00');
        $this->api('GET', "/api/spaces/{$this->pf->id}/payables?status=overdue")->assertJsonCount(2, 'data');
        $this->api('GET', "/api/spaces/{$this->pf->id}/payables?status=open")->assertJsonCount(4, 'data');
    }

    private function api(string $method, string $uri, array $data = [], array $headers = []): TestResponse
    {
        return $this->withToken($this->token)->json($method, $uri, $data, $headers);
    }

    private function account(Space $space, string $name, string $opening, string $date): int
    {
        return $this->api('POST', "/api/spaces/{$space->id}/accounts", ['name' => $name, 'opening_balance' => $opening, 'opening_balance_date' => $date])->json('data.id');
    }

    private function create(array $body, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/payables", $body, ['Idempotency-Key' => $key]);
    }

    private function single(string $amount, string $due = '2026-03-20'): int
    {
        static $sequence = 0;

        return $this->create(['kind' => 'single', 'description' => 'Despesa '.$amount, 'amount' => $amount, 'due_date' => $due], 'cria-'.++$sequence)
            ->assertCreated()->json('data.payables.0.id');
    }

    private function payableUrl(int $id): string
    {
        return "/api/spaces/{$this->pf->id}/payables/{$id}";
    }

    private function pay(int $payable, int $account, string $amount, string $date, string $key): TestResponse
    {
        return $this->api('POST', $this->payableUrl($payable).'/payments', ['account_id' => $account, 'amount' => $amount, 'paid_on' => $date], ['Idempotency-Key' => $key]);
    }

    private function reverse(int $payment, string $reason, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/payments/{$payment}/reversal", ['reason' => $reason], ['Idempotency-Key' => $key]);
    }

    private function correct(int $payment, int $account, string $amount, string $date, string $reason, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/payments/{$payment}/correction", [
            'reason' => $reason, 'account_id' => $account, 'amount' => $amount, 'paid_on' => $date,
        ], ['Idempotency-Key' => $key]);
    }

    private function summary(): TestResponse
    {
        return $this->api('GET', "/api/spaces/{$this->pf->id}/summary");
    }

    private function assertBalance(int $account, string $expected): void
    {
        $this->api('GET', "/api/spaces/{$this->pf->id}/accounts/{$account}")->assertJsonPath('data.balance', $expected);
    }
}
