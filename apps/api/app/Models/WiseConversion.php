<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasOne;

class WiseConversion extends Model
{
    protected $fillable = ['space_id', 'account_id', 'user_id', 'effective_date', 'details', 'reverses_id'];

    public function reversal(): HasOne
    {
        return $this->hasOne(self::class, 'reverses_id');
    }

    protected function casts(): array
    {
        return ['details' => 'array'];
    }
}
