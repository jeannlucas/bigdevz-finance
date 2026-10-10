<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Trilha de edição, cancelamento e encerramento de obrigações, recorrências e cartões. */
class ObligationChange extends Model
{
    protected $fillable = ['space_id', 'user_id', 'subject', 'subject_id', 'action', 'before', 'after', 'reason'];

    protected function casts(): array
    {
        return ['before' => 'array', 'after' => 'array'];
    }
}
