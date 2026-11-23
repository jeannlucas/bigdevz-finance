<?php

namespace Tests\Feature;

use App\Models\Payable;
use App\Models\PayablePlan;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Carbon;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * PEND-007 / AC-FIN-032: Carnês e parcelamentos com valores reajustáveis e datas customizadas por parcela.
 */
class EditableInstallmentPlanTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-03-15 12:00:00', 'America/Sao_Paulo'));
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        $this->token = $this->postJson('/api/auth/login', [
            'email' => $this->user->email,
            'password' => 'password',
            'device_name' => 't',
        ])->json('token');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(string $method, string $uri, array $data = [], array $headers = []): TestResponse
    {
        return $this->withToken($this->token)->json($method, $uri, $data, $headers);
    }

    private function create(array $body, string $key): TestResponse
    {
        return $this->api('POST', "/api/spaces/{$this->pf->id}/payables", $body, ['Idempotency-Key' => $key]);
    }

    public function test_bank_day_preview_is_opt_in_and_preserves_the_reference_day(): void
    {
        $url = "/api/spaces/{$this->pf->id}/payables/preview";
        $body = ['total' => '409.34', 'installment_count' => 3, 'first_due_date' => '2026-11-15'];

        $this->api('POST', $url, $body)->assertOk()
            ->assertJsonPath('data.0.due_date', '2026-11-15');

        $this->api('POST', $url, $body + ['suggest_next_bank_day' => true])->assertOk()
            ->assertJsonPath('data.0.due_date', '2026-11-16')
            ->assertJsonPath('data.1.due_date', '2026-12-15')
            ->assertJsonPath('data.2.due_date', '2027-01-15')
            ->assertJsonPath('data.0.amount', '136.45')
            ->assertJsonPath('data.2.amount', '136.44')
            ->assertJsonCount(3, 'data');

        foreach ([
            '2026-02-14' => '2026-02-18',
            '2026-04-03' => '2026-04-06',
            '2026-06-04' => '2026-06-05',
            '2026-10-31' => '2026-11-03',
            '2026-12-31' => '2027-01-04',
        ] as $base => $expected) {
            $this->api('POST', $url, [
                'total' => '1.00',
                'installment_count' => 1,
                'first_due_date' => $base,
                'suggest_next_bank_day' => true,
            ])->assertOk()->assertJsonPath('data.0.due_date', $expected);
        }

        $this->assertSame(0, $this->pf->payables()->count());
    }

    public function test_custom_installments_are_persisted_with_exact_dates_and_amounts(): void
    {
        // Cenário sintético PEND-007:
        // Parcela 1: R$ 135,17 em 2026-11-16 (segunda-feira útil após dia 15 domingo)
        // Parcela 2: R$ 136,44 em 2026-12-15
        // Parcela 3: R$ 137,73 em 2027-01-15
        // Total: R$ 409,34
        $body = [
            'kind' => 'installment',
            'description' => 'Carnê IPTU Reajustável',
            'payee' => 'Prefeitura Municipal',
            'total' => '409.34',
            'installment_count' => 3,
            'first_due_date' => '2026-11-16',
            'installments' => [
                ['number' => 1, 'amount' => '135.17', 'due_date' => '2026-11-16'],
                ['number' => 2, 'amount' => '136.44', 'due_date' => '2026-12-15'],
                ['number' => 3, 'amount' => '137.73', 'due_date' => '2027-01-15'],
            ],
        ];

        $response = $this->create($body, 'carne-iptu-1')->assertCreated();

        $response->assertJsonPath('data.kind', 'installment')
            ->assertJsonPath('data.payables.0.amount', '135.17')
            ->assertJsonPath('data.payables.0.due_date', '2026-11-16')
            ->assertJsonPath('data.payables.0.plan.installment_number', 1)
            ->assertJsonPath('data.payables.1.amount', '136.44')
            ->assertJsonPath('data.payables.1.due_date', '2026-12-15')
            ->assertJsonPath('data.payables.1.plan.installment_number', 2)
            ->assertJsonPath('data.payables.2.amount', '137.73')
            ->assertJsonPath('data.payables.2.due_date', '2027-01-15')
            ->assertJsonPath('data.payables.2.plan.installment_number', 3);

        // Banco de dados: 3 parcelas associadas ao plano com total_cents exato
        $planId = $response->json('data.payables.0.plan.id');
        $this->assertNotNull($planId);
        $plan = PayablePlan::query()->findOrFail($planId);
        $this->assertSame(40934, $plan->total_cents);
        $this->assertSame(3, $plan->installment_count);
        $this->assertSame('2026-11-16', $plan->first_due_date->toDateString());

        $payables = Payable::query()->where('plan_id', $planId)->orderBy('installment_number')->get();
        $this->assertCount(3, $payables);
        $this->assertSame([13517, 13644, 13773], $payables->pluck('amount_cents')->all());
        $this->assertSame(['2026-11-16', '2026-12-15', '2027-01-15'], $payables->pluck('due_date')->map->toDateString()->all());

        // Replay idempotente com a mesma chave devolve 200 com replayed=true
        $this->create($body, 'carne-iptu-1')
            ->assertOk()
            ->assertJsonPath('data.replayed', true)
            ->assertJsonPath('data.payables.0.amount', '135.17');
    }

    public function test_custom_installments_rejected_when_sum_diverges_from_total(): void
    {
        $body = [
            'kind' => 'installment',
            'description' => 'Carnê IPTU Divergente',
            'total' => '400.00', // Divergente: soma dá 409.34
            'installment_count' => 3,
            'first_due_date' => '2026-11-16',
            'installments' => [
                ['number' => 1, 'amount' => '135.17', 'due_date' => '2026-11-16'],
                ['number' => 2, 'amount' => '136.44', 'due_date' => '2026-12-15'],
                ['number' => 3, 'amount' => '137.73', 'due_date' => '2027-01-15'],
            ],
        ];

        $this->create($body, 'carne-divergente')
            ->assertStatus(422)
            ->assertJsonValidationErrors('total');
    }

    public function test_custom_installments_rejected_when_count_mismatches(): void
    {
        $body = [
            'kind' => 'installment',
            'description' => 'Carnê Quantidade Incompatível',
            'total' => '409.34',
            'installment_count' => 3,
            'first_due_date' => '2026-11-16',
            'installments' => [
                ['number' => 1, 'amount' => '135.17', 'due_date' => '2026-11-16'],
                ['number' => 2, 'amount' => '274.17', 'due_date' => '2026-12-15'],
            ], // Apenas 2 itens para count=3
        ];

        $this->create($body, 'carne-count-mismatch')
            ->assertStatus(422)
            ->assertJsonValidationErrors('installments');
    }

    public function test_custom_installments_rejected_when_dates_are_out_of_order(): void
    {
        $body = [
            'kind' => 'installment',
            'description' => 'Carnê Datas Invertidas',
            'total' => '409.34',
            'installment_count' => 3,
            'first_due_date' => '2026-11-16',
            'installments' => [
                ['number' => 1, 'amount' => '135.17', 'due_date' => '2026-11-16'],
                ['number' => 2, 'amount' => '136.44', 'due_date' => '2026-10-15'], // Data anterior à parcela 1
                ['number' => 3, 'amount' => '137.73', 'due_date' => '2027-01-15'],
            ],
        ];

        $this->create($body, 'carne-dates-inverted')
            ->assertStatus(422)
            ->assertJsonValidationErrors('installments');
    }

    public function test_legacy_flow_without_installments_array_maintains_deterministic_division(): void
    {
        $body = [
            'kind' => 'installment',
            'description' => 'Notebook Legado',
            'total' => '100.00',
            'installment_count' => 3,
            'first_due_date' => '2026-01-31',
        ];

        $response = $this->create($body, 'parcela-legada')->assertCreated();

        $response->assertJsonPath('data.payables.0.amount', '33.34')
            ->assertJsonPath('data.payables.0.due_date', '2026-01-31')
            ->assertJsonPath('data.payables.1.amount', '33.33')
            ->assertJsonPath('data.payables.1.due_date', '2026-02-28')
            ->assertJsonPath('data.payables.2.amount', '33.33')
            ->assertJsonPath('data.payables.2.due_date', '2026-03-31');
    }
}
