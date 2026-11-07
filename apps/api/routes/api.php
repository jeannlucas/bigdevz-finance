<?php

use App\Http\Controllers\Api\AccountController;
use App\Http\Controllers\Api\AgreementController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\CardController;
use App\Http\Controllers\Api\InstallmentController;
use App\Http\Controllers\Api\LoanController;
use App\Http\Controllers\Api\PayableController;
use App\Http\Controllers\Api\PaymentController;
use App\Http\Controllers\Api\ReceiptController;
use App\Http\Controllers\Api\ReceiptReversalController;
use App\Http\Controllers\Api\RecurrenceController;
use App\Http\Controllers\Api\SpaceController;
use App\Http\Controllers\Api\StatementController;
use App\Http\Controllers\Api\TransferController;
use Illuminate\Support\Facades\Route;

// IDs são numéricos e cabem em BIGINT; o resto vira 404 antes do banco.
Route::pattern('space', '[1-9][0-9]{0,17}');
Route::pattern('account', '[1-9][0-9]{0,17}');
Route::pattern('agreement', '[1-9][0-9]{0,17}');
Route::pattern('installment', '[1-9][0-9]{0,17}');
Route::pattern('receipt', '[1-9][0-9]{0,17}');
foreach (['payable', 'payment', 'recurrence', 'card', 'transfer'] as $parameter) {
    Route::pattern($parameter, '[1-9][0-9]{0,17}');
}

Route::get('/up', fn () => response()->json(['status' => 'ok']));

Route::post('/auth/login', [AuthController::class, 'login'])->middleware('throttle:login');

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/me', [AuthController::class, 'me']);
    Route::patch('/me', [AuthController::class, 'updateProfile']);

    Route::get('/spaces', [SpaceController::class, 'index']);
    Route::prefix('/spaces/{space}')->group(function () {
        Route::get('/summary', [SpaceController::class, 'summary']);
        Route::get('/statement', [StatementController::class, 'index']);
        Route::get('/accounts', [AccountController::class, 'index']);
        Route::post('/accounts', [AccountController::class, 'store']);
        Route::get('/accounts/{account}', [AccountController::class, 'show']);
        Route::patch('/accounts/{account}', [AccountController::class, 'update']);
        Route::post('/accounts/{account}/archive', [AccountController::class, 'archive']);
        Route::post('/accounts/{account}/unarchive', [AccountController::class, 'unarchive']);
        Route::post('/accounts/{account}/opening-adjustment', [AccountController::class, 'adjustOpening']);
        Route::get('/transfers', [TransferController::class, 'index']);
        Route::post('/transfers', [TransferController::class, 'store']);
        Route::get('/transfers/{transfer}', [TransferController::class, 'show']);
        Route::get('/loans', [LoanController::class, 'index']);
        Route::post('/loans', [LoanController::class, 'store']);
        Route::get('/loans/{loan}', [LoanController::class, 'show']);
        Route::get('/agreements', [AgreementController::class, 'index']);
        Route::post('/agreements', [AgreementController::class, 'store']);
        Route::get('/agreements/{agreement}', [AgreementController::class, 'show']);
        Route::get('/installments/{installment}', [InstallmentController::class, 'show']);
        Route::post('/installments/{installment}/receipts', [ReceiptController::class, 'store']);
        Route::post('/receipts/{receipt}/reversal', [ReceiptReversalController::class, 'reverse']);
        Route::post('/receipts/{receipt}/correction', [ReceiptReversalController::class, 'correct']);

        // A pagar.
        Route::get('/payables', [PayableController::class, 'index']);
        Route::post('/payables', [PayableController::class, 'store']);
        Route::post('/payables/preview', [PayableController::class, 'preview']);
        Route::post('/payables/recurrence-preview', [PayableController::class, 'recurrencePreview']);
        Route::get('/payables/{payable}', [PayableController::class, 'show']);
        Route::patch('/payables/{payable}', [PayableController::class, 'update']);
        Route::post('/payables/{payable}/cancel', [PayableController::class, 'cancel']);
        Route::post('/payables/{payable}/payments', [PaymentController::class, 'store']);
        Route::post('/payments/{payment}/reversal', [PaymentController::class, 'reverse']);
        Route::post('/payments/{payment}/correction', [PaymentController::class, 'correct']);
        Route::get('/recurrences', [RecurrenceController::class, 'index']);
        Route::patch('/recurrences/{recurrence}', [RecurrenceController::class, 'update']);
        Route::post('/recurrences/{recurrence}/end', [RecurrenceController::class, 'end']);
        Route::get('/cards', [CardController::class, 'index']);
        Route::post('/cards', [CardController::class, 'store']);
        Route::post('/cards/{card}/archive', [CardController::class, 'archive']);
        Route::post('/cards/{card}/unarchive', [CardController::class, 'unarchive']);
    });
});
