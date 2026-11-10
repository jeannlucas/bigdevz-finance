<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SpaceClosingLog extends Model
{
    public const ACTION_CLOSED = 'closed';

    public const ACTION_REOPENED = 'reopened';

    protected $fillable = [
        'space_id',
        'user_id',
        'action',
        'closed_until',
        'previous_closed_until',
        'reason',
    ];

    protected function casts(): array
    {
        return [
            'closed_until' => 'date',
            'previous_closed_until' => 'date',
        ];
    }

    /** @return BelongsTo<Space, $this> */
    public function space(): BelongsTo
    {
        return $this->belongsTo(Space::class);
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
