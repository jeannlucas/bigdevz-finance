<?php

namespace App\Http\Controllers\Api;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Wise\PostConversion;
use App\Domain\Wise\Currency;
use App\Http\Controllers\Api\Concerns\HandlesIdempotency;
use App\Http\Controllers\Controller;
use App\Http\Resources\WiseCurrencyResource;
use App\Models\WiseConversion;
use App\Models\WiseCurrency;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class WiseWalletController extends Controller
{
    use HandlesIdempotency;

    public function storeCurrency(Request $request, string $space, string $account, IdempotentOperations $keys): JsonResponse
    {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), 'create_account');
        $account = $space->accounts()->where('bank_id', 'wise')->findOrFail($account);
        $key = $this->idempotencyKey($request);
        $operation = IdempotentOperations::WISE_CURRENCY;
        $payload = ['currency' => $request->input('currency'), 'opening_balance' => $request->input('opening_balance')];
        $fingerprint = IdempotentOperations::fingerprint($operation, $account->id, $payload);
        $result = $keys->run($request->user(), $space, $key, $operation, $fingerprint, function () use ($space, $account, $payload) {
            $data = Validator::make($payload, [
                'currency' => ['required', 'string', Rule::in(array_diff(array_keys(Currency::SCALES), ['BRL']))],
                'opening_balance' => ['nullable', 'string'],
            ])->validate();
            $account = $space->accounts()->where('bank_id', 'wise')->lockForUpdate()->findOrFail($account->id);
            $currency = $data['currency'];
            if ($account->isArchived() || $account->wiseCurrencies()->where('currency', $currency)->exists()) {
                throw ValidationException::withMessages(['currency' => 'Conta arquivada ou moeda já cadastrada.']);
            }
            $row = $account->wiseCurrencies()->create([
                'space_id' => $space->id,
                'currency' => $currency,
                'opening_units' => isset($data['opening_balance']) ? Currency::parse($currency, $data['opening_balance']) : 0,
            ]);

            return ['wise_currency_id' => $row->id];
        });
        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }
        $row = WiseCurrency::query()->where('space_id', $space->id)->findOrFail($result->ref('wise_currency_id'));

        return response()->json([
            'data' => new WiseCurrencyResource($row),
            'idempotency' => $this->idempotency($key, $result),
        ], $result->replayed ? 200 : 201);
    }

    public function quote(Request $request, string $space, string $account, string $currency): WiseCurrencyResource
    {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), 'adjust_opening_balance');

        return DB::transaction(function () use ($request, $space, $account, $currency) {
            $account = $space->accounts()->where('bank_id', 'wise')->lockForUpdate()->findOrFail($account);
            $row = $account->wiseCurrencies()->where('currency', $currency)->firstOrFail();
            $data = $request->validate([
                'brl_rate' => ['required', 'string', 'regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,8})?$/D'],
                'quoted_on' => ['required', 'date_format:Y-m-d', 'before_or_equal:today'],
            ]);
            if (trim($data['brl_rate'], '0.') === '') {
                throw ValidationException::withMessages(['brl_rate' => 'Informe uma cotação maior que zero.']);
            }
            if ($account->isArchived() || ($row->quoted_on !== null && $data['quoted_on'] < $row->quoted_on)) {
                throw ValidationException::withMessages(['quoted_on' => 'A conta está arquivada ou a cotação é anterior à atual.']);
            }
            $row->update($data);

            return new WiseCurrencyResource($row);
        });
    }

    public function marketRate(Request $request, string $space, string $account, string $currency): JsonResponse
    {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), 'adjust_opening_balance');
        $space->accounts()->where('bank_id', 'wise')->findOrFail($account);

        $currency = strtoupper($currency);
        if ($currency === 'BRL' || ! array_key_exists($currency, Currency::SCALES)) {
            throw ValidationException::withMessages(['currency' => 'Moeda inválida ou não suportada para cotação.']);
        }

        $cacheKey = "wise:market_rate:{$currency}";
        $rateData = Cache::remember($cacheKey, now()->addMinutes(15), function () use ($currency) {
            try {
                $response = Http::timeout(5)->get("https://economia.awesomeapi.com.br/last/{$currency}-BRL");
                if (! $response->successful()) {
                    return null;
                }
                $json = $response->json();
                $pair = "{$currency}BRL";
                if (! isset($json[$pair]['bid'])) {
                    return null;
                }
                $bid = (string) $json[$pair]['bid'];
                if (! preg_match('/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,8})?$/D', $bid) || trim($bid, '0.') === '') {
                    return null;
                }

                return [
                    'currency' => $currency,
                    'target' => 'BRL',
                    'rate' => $bid,
                    'quoted_on' => today()->toDateString(),
                ];
            } catch (\Throwable) {
                return null;
            }
        });

        if ($rateData === null) {
            Cache::forget($cacheKey);
            throw ValidationException::withMessages(['message' => 'Cotação de mercado não disponível para esta moeda no momento.']);
        }

        return response()->json(['data' => $rateData]);
    }

    public function history(Request $request, string $space, string $account): JsonResponse
    {
        $space = $this->space($request, $space);
        $account = $space->accounts()->where('bank_id', 'wise')->findOrFail($account);

        return response()->json(WiseConversion::query()->where('space_id', $space->id)->where('account_id', $account->id)
            ->withExists('reversal')->orderByDesc('effective_date')->orderByDesc('id')->paginate(30));
    }

    public function convert(Request $request, string $space, string $account, PostConversion $post, IdempotentOperations $keys): JsonResponse
    {
        return $this->conversion($request, $space, $account, $post, $keys);
    }

    public function reverse(Request $request, string $space, string $account, int $conversion, PostConversion $post, IdempotentOperations $keys): JsonResponse
    {
        return $this->conversion($request, $space, $account, $post, $keys, $conversion);
    }

    private function conversion(Request $request, string $space, string $account, PostConversion $post, IdempotentOperations $keys, ?int $reverses = null): JsonResponse
    {
        $space = $this->space($request, $space);
        $space->ensureCan($request->user(), $reverses === null ? 'transfer_funds' : 'reverse_transfer');
        $account = $space->accounts()->where('bank_id', 'wise')->findOrFail($account);
        $key = $this->idempotencyKey($request);
        $operation = $reverses === null ? IdempotentOperations::WISE_CONVERSION : IdempotentOperations::WISE_REVERSAL;
        $payload = $request->only(['source', 'destination', 'debited', 'credited', 'fee', 'fee_currency', 'effective_date']);
        ksort($payload);
        $fingerprint = IdempotentOperations::fingerprint($operation, $account->id, [$reverses, $payload]);
        $result = $keys->run($request->user(), $space, $key, $operation, $fingerprint, function () use ($request, $space, $account, $post, $payload, $reverses) {
            $account = $space->accounts()->where('bank_id', 'wise')->lockForUpdate()->findOrFail($account->id);
            $date = Validator::make($payload, ['effective_date' => ['required', 'date_format:Y-m-d', 'before_or_equal:today']])->validate()['effective_date'];
            if ($reverses !== null) {
                $original = WiseConversion::query()->where('account_id', $account->id)->where('space_id', $space->id)->findOrFail($reverses);
                if ($original->reverses_id !== null || $date < $original->effective_date || WiseConversion::query()->where('reverses_id', $original->id)->exists()) {
                    throw ValidationException::withMessages(['conversion' => 'A conversão já foi estornada ou a data é incompatível.']);
                }

                return $post->handle($request->user(), $space, $account, $date, [], array_map(fn (int $units) => -$units, $original->details['deltas']), $original->id);
            }

            $codes = Rule::in(array_keys(Currency::SCALES));
            $data = Validator::make($payload, [
                'source' => ['required', 'string', $codes],
                'destination' => ['required', 'string', 'different:source', $codes],
                'debited' => ['required', 'string'],
                'credited' => ['required', 'string'],
                'fee' => ['nullable', 'required_with:fee_currency', 'string'],
                'fee_currency' => ['nullable', 'required_with:fee', 'string', $codes],
            ])->validate();
            $debit = Currency::parse($data['source'], $data['debited'], 'debited');
            $credit = Currency::parse($data['destination'], $data['credited'], 'credited');
            if ($debit === 0 || $credit === 0) {
                throw ValidationException::withMessages(['debited' => 'Informe valores maiores que zero.']);
            }
            $deltas = [$data['source'] => -$debit, $data['destination'] => $credit];
            if (isset($data['fee'], $data['fee_currency'])) {
                $feeCurrency = $data['fee_currency'];
                $deltas[$feeCurrency] = ($deltas[$feeCurrency] ?? 0) - Currency::parse($feeCurrency, $data['fee'], 'fee');
            }

            return $post->handle($request->user(), $space, $account, $date, $data, $deltas);
        });
        if ($result->rejected()) {
            return $this->rejection($key, $result);
        }
        $row = WiseConversion::query()->where('account_id', $account->id)->where('space_id', $space->id)->findOrFail($result->ref('wise_conversion_id'));

        return response()->json(['data' => $row, 'idempotency' => $this->idempotency($key, $result)], $result->replayed ? 200 : 201);
    }
}
