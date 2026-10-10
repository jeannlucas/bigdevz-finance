<?php

use App\Http\Controllers\Api\AccountController;
use App\Http\Controllers\Api\AgreementController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\InstallmentController;
use App\Http\Controllers\Api\ReceiptController;
use App\Http\Controllers\Api\ReceiptReversalController;
use App\Http\Controllers\Api\SpaceController;
use Illuminate\Support\Facades\Route;

// IDs são numéricos e cabem em BIGINT; o resto vira 404 antes do banco.
Route::pattern('space', '[1-9][0-9]{0,17}');
Route::pattern('account', '[1-9][0-9]{0,17}');
Route::pattern('agreement', '[1-9][0-9]{0,17}');
Route::pattern('installment', '[1-9][0-9]{0,17}');
Route::pattern('receipt', '[1-9][0-9]{0,17}');

Route::post('/auth/login', [AuthController::class, 'login'])->middleware('throttle:login');

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/me', [AuthController::class, 'me']);

    Route::get('/spaces', [SpaceController::class, 'index']);
    Route::prefix('/spaces/{space}')->group(function () {
        Route::get('/summary', [SpaceController::class, 'summary']);
        Route::get('/accounts', [AccountController::class, 'index']);
        Route::post('/accounts', [AccountController::class, 'store']);
        Route::get('/accounts/{account}', [AccountController::class, 'show']);
        Route::get('/agreements', [AgreementController::class, 'index']);
        Route::post('/agreements', [AgreementController::class, 'store']);
        Route::get('/agreements/{agreement}', [AgreementController::class, 'show']);
        Route::get('/installments/{installment}', [InstallmentController::class, 'show']);
        Route::post('/installments/{installment}/receipts', [ReceiptController::class, 'store']);
        Route::post('/receipts/{receipt}/reversal', [ReceiptReversalController::class, 'reverse']);
        Route::post('/receipts/{receipt}/correction', [ReceiptReversalController::class, 'correct']);
    });
});
