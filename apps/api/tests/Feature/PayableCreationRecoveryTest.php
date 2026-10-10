<?php

namespace Tests\Feature;

use App\Models\AccountMovement;
use App\Models\Payable;
use App\Models\Recurrence;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/** Cadastro de A pagar: replay pela mesma chave e revisão de recorrências, em PostgreSQL real. */
class PayableCreationRecoveryTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        $this->today('2026-03-15');
        [$this->user, $this->pf] = $this->userWithSpaces();
        $this->token = $this->postJson('/api/auth/login', ['email' => $this->user->email, 'password' => 'password', 'device_name' => 't'])->json('token');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_replay_after_edit_or_cancel_returns_the_original_records(): void
    {
        $single = ['kind' => 'single', 'description' => 'Conserto', 'amount' => '300.00', 'due_date' => '2026-03-20'];
        $id = $this->create($single, 'avulsa')->assertCreated()->json('data.payables.0.id');
        $this->api('POST', "/api/spaces/{$this->pf->id}/payables/{$id}/cancel", ['reason' => 'Desisti'])->assertOk();
        $this->create($single, 'avulsa')->assertOk()->assertJsonPath('data.replayed', true)
            ->assertJsonPath('data.payables.0.id', $id)->assertJsonPath('data.payables.0.status', 'cancelled');

        $plan = ['kind' => 'installment', 'description' => 'Notebook', 'total' => '100.00', 'installment_count' => 3, 'first_due_date' => '2026-04-10'];
        $ids = $this->create($plan, 'parcelas')->assertCreated()->json('data.payables.*.id');
        $this->api('PATCH', "/api/spaces/{$this->pf->id}/payables/{$ids[0]}", ['amount' => '40.00'])->assertOk();
        $this->create($plan, 'parcelas')->assertOk()->assertJsonPath('data.payables.*.id', $ids)
            ->assertJsonPath('data.payables.0.amount', '40.00');

        $this->assertSame(4, Payable::query()->where('space_id', $this->pf->id)->count());
    }

    public function test_recurrence_preview_shows_the_exact_period_without_writing(): void
    {
        $this->preview('1500.00', '2026-01-31')
            ->assertOk()
            ->assertJsonPath('data.reference_day', 31)
            ->assertJsonPath('data.horizon', '2027-03-01')
            ->assertJsonPath('data.approved_until', '2027-03-01')
            ->assertJsonPath('data.first_due_date', '2026-01-31')
            ->assertJsonPath('data.last_due_date', '2027-03-31')
            ->assertJsonPath('data.count', 15)
            ->assertJsonPath('data.past_count', 2)
            ->assertJsonPath('data.past_total', '3000.00')
            ->assertJsonPath('data.total', '22500.00')
            ->assertJsonPath('data.items.1.due_date', '2026-02-28')
            ->assertJsonPath('data.items.1.past', true)
            ->assertJsonPath('data.items.2.past', false);
        $this->preview('100.00', '2026-01-31', '2026-06-30')->assertJsonPath('data.count', 6)->assertJsonPath('data.approved_until', '2026-06-01');
        $this->assertSame(0, Recurrence::query()->where('space_id', $this->pf->id)->count(), 'prévia não grava');
        $this->assertSame(0, Payable::query()->where('space_id', $this->pf->id)->count());

        $this->today('2028-03-15');
        $this->preview('100.00', '2028-01-31')->assertJsonPath('data.items.1.due_date', '2028-02-29');

        // Período longo demais: mensagem clara, sem truncar.
        $this->preview('100.00', '2010-01-15')->assertStatus(422)->assertJsonValidationErrors('start_date');
        $this->preview('100.00', '2030-01-15')->assertStatus(422)->assertJsonValidationErrors('start_date');
    }

    public function test_past_occurrences_require_explicit_confirmation(): void
    {
        $movements = AccountMovement::query()->count();
        $body = $this->recurring('2026-01-31', '2027-03-01', false);
        $this->create($body, 'sem-confirmar')->assertStatus(422)->assertJsonValidationErrors('confirm_past')
            ->assertJsonPath('idempotency.status', 'rejected');
        $this->assertSame(0, Recurrence::query()->where('space_id', $this->pf->id)->count());

        $ids = $this->create($this->recurring('2026-01-31', '2027-03-01', true), 'confirmada')->assertCreated()->json('data.payables.*.id');
        $this->assertCount(15, $ids);
        $this->assertSame($movements, AccountMovement::query()->count(), 'criar obrigações não movimenta contas');
        $this->assertSame(0, Payable::query()->where('space_id', $this->pf->id)->sum('paid_cents'), 'gerar não paga nada');
    }

    public function test_created_set_is_the_approved_one_even_if_the_date_changes(): void
    {
        // Revisado em 15/03 (até mar/2027), enviado em 15/04 (horizonte abr/2027).
        $body = $this->recurring('2026-01-31', '2027-03-01', true);
        $this->today('2026-04-15');
        $ids = $this->create($body, 'aprovada')->assertCreated()->json('data.payables.*.id');
        $this->assertCount(15, $ids, 'exatamente o conjunto aprovado');
        $recurrence = Recurrence::query()->where('space_id', $this->pf->id)->sole();
        $this->assertSame('2027-03-01', $recurrence->initial_until->toDateString());

        // A geração automática estende depois; é um conjunto separado.
        Artisan::call('payables:generate');
        $this->assertSame(16, Payable::query()->where('recurrence_id', $recurrence->id)->count());

        // Replay meses depois: o mesmo conjunto inicial, sem nova rodada.
        $this->today('2026-06-15');
        $this->create($body, 'aprovada')->assertOk()->assertJsonPath('data.replayed', true)->assertJsonPath('data.payables.*.id', $ids);
        $this->assertSame(16, Payable::query()->where('recurrence_id', $recurrence->id)->count());
        Artisan::call('payables:generate');
        $this->assertSame(18, Payable::query()->where('recurrence_id', $recurrence->id)->distinct()->count('cycle'), 'scheduler não duplica ciclos');
    }

    public function test_changed_effective_result_requires_a_new_review(): void
    {
        // Período aprovado além do horizonte do momento do envio.
        $this->create($this->recurring('2026-01-31', '2027-04-01', true), 'alem')
            ->assertStatus(422)->assertJsonValidationErrors('approved_until');
        // Revisada em 15/03 sem passadas; enviada em 25/03, a de 20/03 já venceu.
        $this->today('2026-03-25');
        $this->create($this->recurring('2026-03-20', '2027-03-01', false), 'virou-passada')
            ->assertStatus(422)->assertJsonValidationErrors('confirm_past');
        $this->assertSame(0, Recurrence::query()->where('space_id', $this->pf->id)->count());
    }

    private function recurring(string $start, string $until, bool $confirmPast): array
    {
        return ['kind' => 'recurring', 'description' => 'Aluguel', 'amount' => '1500.00', 'start_date' => $start,
            'approved_until' => $until, 'confirm_past' => $confirmPast];
    }

    private function today(string $date): void
    {
        Carbon::setTestNow(Carbon::parse($date.' 12:00:00', 'America/Sao_Paulo'));
    }

    private function api(string $method, string $uri, array $data = [], array $headers = []): TestResponse
    {
        return $this->withToken($this->token)->json($method, $uri, $data, $headers);
    }

    private function create(array $body, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/payables", $body, ['Idempotency-Key' => $key]);
    }

    private function preview(string $amount, string $start, ?string $end = null): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/payables/recurrence-preview", ['amount' => $amount, 'start_date' => $start, 'end_date' => $end]);
    }
}
