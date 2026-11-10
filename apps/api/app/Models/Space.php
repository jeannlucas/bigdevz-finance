<?php

namespace App\Models;

use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

class Space extends Model
{
    public const PF = 'PF';

    public const PJ = 'PJ';

    public const ROLE_ADMIN = 'administrador';

    public const ROLE_FINANCIAL = 'financeiro';

    public const ROLE_OPERATOR = 'operador';

    public const ROLE_ACCOUNTANT = 'contador';

    public const ROLES = [
        self::ROLE_ADMIN,
        self::ROLE_FINANCIAL,
        self::ROLE_OPERATOR,
        self::ROLE_ACCOUNTANT,
    ];

    protected $fillable = ['kind', 'name', 'closed_until'];

    protected function casts(): array
    {
        return [
            'closed_until' => 'date',
        ];
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @return BelongsToMany<User, $this> */
    public function members(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'space_users')
            ->withPivot('role')
            ->withTimestamps();
    }

    public function roleFor(User $user): string
    {
        if ($this->kind === self::PF) {
            return self::ROLE_ADMIN;
        }

        if ($this->pivot && isset($this->pivot->user_id) && $this->pivot->user_id === $user->id && isset($this->pivot->role)) {
            return (string) $this->pivot->role;
        }

        $membership = $this->members()->where('user_id', $user->id)->first();
        if ($membership && $membership->pivot) {
            return (string) $membership->pivot->role;
        }

        if ($this->user_id === $user->id) {
            return self::ROLE_ADMIN;
        }

        return self::ROLE_OPERATOR;
    }

    public function ensureCan(User $user, string $ability): void
    {
        $role = $this->roleFor($user);

        if ($role === self::ROLE_ADMIN) {
            return;
        }

        $forbidden = match ($ability) {
            'cancel_payable',
            'cancel_agreement',
            'reverse_receipt',
            'reverse_payment',
            'adjust_opening_balance' => in_array($role, [self::ROLE_OPERATOR, self::ROLE_ACCOUNTANT], true),

            'move_money',
            'create_payable',
            'edit_payable',
            'pay_payable',
            'create_agreement',
            'edit_agreement',
            'receive_installment',
            'transfer_funds',
            'create_loan',
            'archive_account',
            'manage_categories' => $role === self::ROLE_ACCOUNTANT,

            'close_period',
            'reopen_period',
            'manage_members' => $role !== self::ROLE_ADMIN,

            'export_data' => $role === self::ROLE_OPERATOR,

            default => false,
        };

        if ($forbidden) {
            abort(403, "Acesso não autorizado para o perfil {$role} nesta operação.");
        }
    }

    public function ensureDateNotClosed(string|CarbonInterface|null $date, string $action = 'esta operação'): void
    {
        if (! $this->closed_until || ! $date) {
            return;
        }

        $closedDate = Carbon::parse($this->closed_until)->format('Y-m-d');
        $operationDate = Carbon::parse($date)->format('Y-m-d');

        if ($operationDate <= $closedDate) {
            $formattedClosed = Carbon::parse($this->closed_until)->format('d/m/Y');
            abort(422, "Período contábil fechado até {$formattedClosed}. Nenhuma movimentação ou alteração pode ser realizada nesta data.");
        }
    }

    /** @return HasMany<Account, $this> */
    public function accounts(): HasMany
    {
        return $this->hasMany(Account::class);
    }

    /** @return HasMany<Agreement, $this> */
    public function agreements(): HasMany
    {
        return $this->hasMany(Agreement::class);
    }

    /** @return HasMany<Installment, $this> */
    public function installments(): HasMany
    {
        return $this->hasMany(Installment::class);
    }

    /** @return HasMany<Receipt, $this> */
    public function receipts(): HasMany
    {
        return $this->hasMany(Receipt::class);
    }

    /** @return HasMany<Payable, $this> */
    public function payables(): HasMany
    {
        return $this->hasMany(Payable::class);
    }

    /** @return HasMany<Recurrence, $this> */
    public function recurrences(): HasMany
    {
        return $this->hasMany(Recurrence::class);
    }

    /** @return HasMany<Card, $this> */
    public function cards(): HasMany
    {
        return $this->hasMany(Card::class);
    }

    /** @return HasMany<Payment, $this> */
    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    /** @return HasMany<Category, $this> */
    public function categories(): HasMany
    {
        return $this->hasMany(Category::class);
    }
}
