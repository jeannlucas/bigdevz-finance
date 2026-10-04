<?php

namespace App\Http\Controllers\Api;

use App\Domain\Receivables\Money;
use App\Http\Controllers\Controller;
use App\Http\Resources\AccountResource;
use App\Rules\MoneyAmount;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class AccountController extends Controller
{
    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        return AccountResource::collection(
            $this->space($request, $space)->accounts()->withSum('movements', 'amount_cents')->orderBy('name')->orderBy('id')->get(),
        );
    }

    public function store(Request $request, string $space): JsonResponse
    {
        $space = $this->space($request, $space);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:80'],
            'opening_balance' => ['required', new MoneyAmount(positive: false)],
            'opening_balance_date' => ['required', 'date_format:Y-m-d'],
        ]);

        $account = $space->accounts()->create([
            'name' => $data['name'],
            'opening_balance_cents' => Money::toCents($data['opening_balance']),
            'opening_balance_date' => $data['opening_balance_date'],
        ]);

        return (new AccountResource($account))->response()->setStatusCode(201);
    }

    public function show(Request $request, string $space, string $account): AccountResource
    {
        return new AccountResource($this->space($request, $space)->accounts()->findOrFail($account));
    }
}
