<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use RuntimeException;

/** Trilha de auditoria permanente e imutável de alterações do sistema financeiro. */
class ObligationChange extends Model
{
    protected $fillable = [
        'space_id',
        'user_id',
        'subject',
        'subject_id',
        'action',
        'before',
        'after',
        'reason',
    ];

    protected static function booted(): void
    {
        static::updating(function (): void {
            throw new RuntimeException('Registros de auditoria são estritamente imutáveis.');
        });

        static::deleting(function (): void {
            throw new RuntimeException('Registros de auditoria são estritamente imutáveis.');
        });
    }

    protected function casts(): array
    {
        return [
            'before' => 'array',
            'after' => 'array',
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

    public function isCritical(): bool
    {
        if (in_array($this->action, ['cancel', 'cancelled', 'reverse', 'reversed', 'reopen', 'reopened', 'adjust_opening'], true)) {
            return true;
        }

        $beforeAmount = $this->before['amount_cents'] ?? $this->before['total_cents'] ?? null;
        $afterAmount = $this->after['amount_cents'] ?? $this->after['total_cents'] ?? null;

        if ($beforeAmount !== null && $afterAmount !== null && $beforeAmount !== $afterAmount) {
            return true;
        }

        return false;
    }
}
