<?php

namespace App\Actions\Wise;

use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\Space;
use App\Models\User;
use App\Models\WiseConversion;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PostConversion
{
    /** Executado dentro da transação da chave idempotente. */
    public function handle(User $user, Space $space, Account $account, string $date, array $details, array $deltas, ?int $reverses = null): array
    {
        $space->ensureDateNotClosed($date, 'conversão Wise');
        if ($account->isArchived() || $date < $account->opening_balance_date->toDateString()) {
            throw ValidationException::withMessages(['effective_date' => 'Informe uma data após a abertura de uma conta ativa.']);
        }

        $currencies = $account->wiseCurrencies()->get()->keyBy('currency');
        foreach ($deltas as $currency => $delta) {
            $row = $currencies->get($currency);
            if ($currency !== 'BRL' && ($row === null || $date < $row->created_at->toDateString())) {
                throw ValidationException::withMessages(['currency' => "A carteira $currency precisa estar ativa na data da operação."]);
            }
            $current = $currency === 'BRL' ? $account->balanceCents() : $row->balanceUnits();
            if ($current + $delta < 0 || $current + $delta > Money::MAX_CENTS || abs($delta) > Money::MAX_CENTS) {
                throw ValidationException::withMessages(['debited' => "O movimento excede o saldo ou o limite de $currency."]);
            }
        }

        $conversion = WiseConversion::query()->create([
            'account_id' => $account->id, 'space_id' => $space->id, 'user_id' => $user->id,
            'effective_date' => $date, 'reverses_id' => $reverses,
            'details' => $details + ['deltas' => $deltas],
        ]);
        foreach (array_filter($deltas) as $currency => $delta) {
            if ($currency === 'BRL') {
                $account->movements()->forceCreate([
                    'wise_conversion_id' => $conversion->id,
                    'amount_cents' => $delta, 'effective_date' => $date,
                ]);
            } else {
                DB::table('wise_currency_movements')->insert([
                    'space_id' => $space->id, 'wise_conversion_id' => $conversion->id,
                    'wise_currency_id' => $currencies[$currency]->id, 'units' => $delta,
                ]);
            }
        }

        return ['wise_conversion_id' => $conversion->id];
    }
}
