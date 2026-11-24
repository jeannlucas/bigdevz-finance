<?php

namespace App\Http\Resources;

use App\Domain\Wise\Currency;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class WiseCurrencyResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'currency' => $this->currency,
            'balance' => Currency::format($this->currency, $this->balanceUnits()),
            'brl_rate' => $this->brl_rate,
            'quoted_on' => $this->quoted_on,
            'opened_at' => $this->created_at->toDateString(),
        ];
    }
}
