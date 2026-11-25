<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class WiseWalletTest extends TestCase
{
    use DatabaseTransactions;

    public function test_wise_currencies_are_registered_once_and_preserve_brl_and_space(): void
    {
        [$user, $pf, $pj] = $this->userWithSpaces();
        $this->actingAs($user, 'sanctum');
        $wise = $pf->accounts()->create([
            'name' => 'Wise',
            'bank_id' => 'wise',
            'opening_balance_cents' => 36000,
            'opening_balance_date' => '2026-01-01',
        ]);
        $url = "/api/spaces/{$pf->id}/accounts/{$wise->id}/wise/currencies";
        $payload = ['currency' => 'USD', 'opening_balance' => '53.27'];
        $this->postJson($url, $payload, ['Idempotency-Key' => 'usd'])->assertCreated()
            ->assertJsonPath('data.balance', '53.27');
        $this->postJson($url, $payload, ['Idempotency-Key' => 'usd'])->assertOk()
            ->assertJsonPath('idempotency.replayed', true);
        $this->postJson($url, [...$payload, 'opening_balance' => '54.27'], ['Idempotency-Key' => 'usd'])->assertConflict();
        $this->postJson($url, $payload, ['Idempotency-Key' => 'duplicate'])->assertUnprocessable();
        $this->postJson($url, ['currency' => 'JPY', 'opening_balance' => '5.10'], ['Idempotency-Key' => 'invalid-scale'])->assertUnprocessable();
        $this->postJson($url, ['currency' => 'KWD', 'opening_balance' => '5.123'], ['Idempotency-Key' => 'kwd'])->assertCreated();
        $this->getJson("/api/spaces/{$pf->id}/accounts")
            ->assertJsonPath('data.0.balance', '360.00')
            ->assertJsonPath('data.0.wise_currencies.0.currency', 'KWD')
            ->assertJsonPath('data.0.wise_currencies.0.balance', '5.123')
            ->assertJsonPath('data.0.wise_currencies.1.currency', 'USD')
            ->assertJsonPath('data.0.wise_currencies.1.balance', '53.27');
        $this->getJson("/api/spaces/{$pj->id}/accounts/{$wise->id}")->assertNotFound();
        $quote = "$url/USD/quote";
        $this->patchJson($quote, ['brl_rate' => '5.650134', 'quoted_on' => today()->toDateString()])
            ->assertOk()->assertJsonPath('data.brl_rate', '5.650134');
        $this->patchJson($quote, ['brl_rate' => '0.000', 'quoted_on' => today()->toDateString()])
            ->assertUnprocessable();
        $this->patchJson("/api/spaces/{$pf->id}/accounts/{$wise->id}", ['name' => 'WISE', 'bank_id' => 'other'])
            ->assertUnprocessable();
        $plain = $pj->accounts()->create(['name' => 'Banco', 'opening_balance_cents' => 0, 'opening_balance_date' => '2026-01-01']);
        $this->postJson("/api/spaces/{$pj->id}/accounts/{$plain->id}/wise/currencies", $payload, ['Idempotency-Key' => 'invalid-account'])
            ->assertNotFound();

    }

    public function test_conversion_and_reversal_post_exact_brl_and_foreign_movements(): void
    {
        [$user, $pf] = $this->userWithSpaces();
        $this->actingAs($user, 'sanctum');
        $wise = $pf->accounts()->create([
            'name' => 'Wise', 'bank_id' => 'wise', 'opening_balance_cents' => 36000,
            'opening_balance_date' => '2026-01-01',
        ]);
        $account = "/api/spaces/{$pf->id}/accounts/{$wise->id}";
        $this->postJson("$account/wise/currencies", ['currency' => 'USD'], ['Idempotency-Key' => 'usd'])->assertCreated();
        $date = today()->toDateString();
        $payload = [
            'source' => 'BRL', 'destination' => 'USD', 'debited' => '280.00', 'credited' => '53.27',
            'fee' => '2.00', 'fee_currency' => 'BRL', 'effective_date' => $date,
        ];
        $id = $this->postJson("$account/wise/conversions", $payload, ['Idempotency-Key' => 'convert'])->assertCreated()->json('data.id');
        $this->postJson("$account/wise/conversions", $payload, ['Idempotency-Key' => 'convert'])->assertOk();
        $this->postJson("$account/wise/conversions", [...$payload, 'credited' => '53.28'], ['Idempotency-Key' => 'convert'])->assertConflict();
        $this->postJson("$account/wise/conversions", $payload, ['Idempotency-Key' => 'unfunded'])->assertUnprocessable();
        $this->getJson("$account/wise/conversions")->assertJsonCount(1, 'data');

        $this->getJson($account)->assertJsonPath('data.balance', '78.00')
            ->assertJsonPath('data.wise_currencies.0.balance', '53.27');
        $this->postJson("$account/wise/conversions/$id/reversal", ['effective_date' => $date], ['Idempotency-Key' => 'reverse'])->assertCreated();
        $this->getJson($account)->assertJsonPath('data.balance', '360.00')
            ->assertJsonPath('data.wise_currencies.0.balance', '0.00');
        $this->getJson("$account/wise/conversions")->assertJsonPath('data.1.reversal_exists', true);
        $this->postJson("$account/wise/conversions/$id/reversal", ['effective_date' => $date], ['Idempotency-Key' => 'reverse'])
            ->assertOk()->assertJsonPath('idempotency.replayed', true);
        $this->postJson("$account/wise/conversions/$id/reversal", ['effective_date' => $date], ['Idempotency-Key' => 'reverse-again'])
            ->assertUnprocessable();

    }

    public function test_existing_brl_transfer_credits_wise_without_changing_foreign_balance(): void
    {
        [$user, $pf] = $this->userWithSpaces();
        $this->actingAs($user, 'sanctum');
        $bank = $pf->accounts()->create([
            'name' => 'Banco', 'opening_balance_cents' => 50000, 'opening_balance_date' => '2026-01-01',
        ]);
        $wise = $pf->accounts()->create([
            'name' => 'Wise', 'bank_id' => 'wise', 'opening_balance_cents' => 0, 'opening_balance_date' => '2026-01-01',
        ]);
        $root = "/api/spaces/{$pf->id}";
        $account = "$root/accounts/{$wise->id}";
        $this->postJson("$account/wise/currencies", ['currency' => 'USD', 'opening_balance' => '53.27'], ['Idempotency-Key' => 'usd'])->assertCreated();
        $this->postJson("$root/transfers", [
            'source_account_id' => $bank->id, 'destination_account_id' => $wise->id,
            'amount' => '360.00', 'transferred_at' => today()->toDateString(),
        ], ['Idempotency-Key' => 'deposit'])->assertCreated();
        $this->getJson("$root/accounts/{$bank->id}")->assertJsonPath('data.balance', '140.00');
        $this->getJson($account)->assertJsonPath('data.balance', '360.00')
            ->assertJsonPath('data.wise_currencies.0.balance', '53.27');
    }

    public function test_market_rate_returns_quoted_rate_and_caches_response(): void
    {
        [$user, $pf] = $this->userWithSpaces();
        $this->actingAs($user, 'sanctum');
        $wise = $pf->accounts()->create([
            'name' => 'Wise',
            'bank_id' => 'wise',
            'opening_balance_cents' => 36000,
            'opening_balance_date' => '2026-01-01',
        ]);
        $url = "/api/spaces/{$pf->id}/accounts/{$wise->id}/wise/currencies/EUR/market-rate";

        Http::fake([
            'https://economia.awesomeapi.com.br/last/EUR-BRL' => Http::response([
                'EURBRL' => [
                    'code' => 'EUR',
                    'codein' => 'BRL',
                    'name' => 'Euro/Real Brasileiro',
                    'bid' => '6.4457',
                    'ask' => '6.4477',
                    'create_date' => '2026-11-25 10:41:49',
                ],
            ], 200),
        ]);

        $response = $this->getJson($url)->assertOk();
        $response->assertJsonPath('data.currency', 'EUR')
            ->assertJsonPath('data.target', 'BRL')
            ->assertJsonPath('data.rate', '6.4457')
            ->assertJsonPath('data.quoted_on', today()->toDateString());

        // Segunda chamada utiliza cache e não dispara nova requisição HTTP
        $this->getJson($url)->assertOk();
        Http::assertSentCount(1);
    }

    public function test_market_rate_validates_currency_and_handles_api_failure(): void
    {
        [$user, $pf] = $this->userWithSpaces();
        $this->actingAs($user, 'sanctum');
        $wise = $pf->accounts()->create([
            'name' => 'Wise',
            'bank_id' => 'wise',
            'opening_balance_cents' => 36000,
            'opening_balance_date' => '2026-01-01',
        ]);

        // Moeda BRL ou inválida responde 422
        $this->getJson("/api/spaces/{$pf->id}/accounts/{$wise->id}/wise/currencies/BRL/market-rate")->assertUnprocessable();
        $this->getJson("/api/spaces/{$pf->id}/accounts/{$wise->id}/wise/currencies/INVALID/market-rate")->assertUnprocessable();

        // Falha na API externa retorna 422 com mensagem amigável
        Http::fake([
            'https://economia.awesomeapi.com.br/last/USD-BRL' => Http::response(null, 500),
        ]);

        $this->getJson("/api/spaces/{$pf->id}/accounts/{$wise->id}/wise/currencies/USD/market-rate")
            ->assertUnprocessable()
            ->assertJsonPath('message', 'Cotação de mercado não disponível para esta moeda no momento.');
    }
}
