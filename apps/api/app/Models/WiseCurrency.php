<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

class WiseCurrency extends Model
{
    protected $fillable = ['space_id', 'currency', 'opening_units', 'brl_rate', 'quoted_on'];

    public function balanceUnits(): int
    {
        return $this->opening_units + (int) ($this->movement_units ?? DB::table('wise_currency_movements')->where('wise_currency_id', $this->id)->sum('units'));
    }

    protected function casts(): array
    {
        return ['opening_units' => 'integer'];
    }
}
