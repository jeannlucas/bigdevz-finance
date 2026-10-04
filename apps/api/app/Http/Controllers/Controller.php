<?php

namespace App\Http\Controllers;

use App\Models\Space;
use Illuminate\Http\Request;

abstract class Controller
{
    /** Espaço do usuário autenticado; ID alheio responde 404, sem revelar existência. */
    protected function space(Request $request, string $spaceId): Space
    {
        return $request->user()->spaces()->findOrFail($spaceId);
    }
}
