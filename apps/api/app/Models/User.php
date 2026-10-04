<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
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
            $user->spaces()->createMany([
                ['kind' => Space::PF, 'name' => 'Pessoal'],
                ['kind' => Space::PJ, 'name' => 'Empresa'],
            ]);
        });
    }

    /** @return HasMany<Space, $this> */
    public function spaces(): HasMany
    {
        return $this->hasMany(Space::class)->orderBy('kind');
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
