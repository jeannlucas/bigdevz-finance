<?php

use Illuminate\Support\Facades\Route;

// A interface é o aplicativo Flutter; a raiz só identifica a API.
Route::get('/', fn () => response()->json(['app' => 'BigDev.Z Finance API', 'docs' => 'docs/api.md']));
