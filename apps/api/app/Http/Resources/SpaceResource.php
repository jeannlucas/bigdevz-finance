<?php

namespace App\Http\Resources;

use App\Models\Space;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Space */
class SpaceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'kind' => $this->kind,
            'name' => $this->name,
            'role' => $request->user() ? $this->roleFor($request->user()) : 'administrador',
            'closed_until' => $this->closed_until?->format('Y-m-d'),
        ];
    }
}
