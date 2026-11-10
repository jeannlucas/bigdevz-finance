<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

#[Fillable(['name', 'email', 'password'])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    /** Todo login nasce com um espaço pessoal (PF) e um empresarial (PJ). */
    protected static function booted(): void
    {
        static::created(function (User $user): void {
            $pf = $user->ownedSpaces()->create(['kind' => Space::PF, 'name' => 'Pessoal']);
            $pj = $user->ownedSpaces()->create(['kind' => Space::PJ, 'name' => 'Empresa']);

            $user->spaces()->attach([
                $pf->id => ['role' => Space::ROLE_ADMIN],
                $pj->id => ['role' => Space::ROLE_ADMIN],
            ]);
        });
    }

    /** @return HasMany<Space, $this> */
    public function ownedSpaces(): HasMany
    {
        return $this->hasMany(Space::class)->orderBy('kind');
    }

    /** @return BelongsToMany<Space, $this> */
    public function spaces(): BelongsToMany
    {
        return $this->belongsToMany(Space::class, 'space_users')
            ->withPivot('role')
            ->withTimestamps()
            ->orderBy('kind');
    }

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }
}
