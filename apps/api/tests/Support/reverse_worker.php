<?php

// Processo independente usado pelo teste de concorrência: estorna (ou corrige,
// com conta/valor/data) um recebimento pelo caso de uso real, em conexão própria.

use App\Actions\Receivables\IdempotencyConflict;
use App\Actions\Receivables\ReverseReceipt;
use App\Models\Space;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;

require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

[, $userId, $spaceId, $receiptId, $key, $reason] = $argv;
$replacement = isset($argv[6]) ? ['account_id' => (int) $argv[6], 'amount_cents' => (int) $argv[7], 'received_on' => $argv[8]] : null;

try {
    $outcome = app(ReverseReceipt::class)->handle(
        User::query()->findOrFail($userId), Space::query()->findOrFail($spaceId),
        (int) $receiptId, $reason, $key, $replacement,
    );
    $result = match (true) {
        $outcome->rejected() => ['result' => 'rejected', 'errors' => $outcome->errors],
        $outcome->replayed => ['result' => 'replayed', 'reversal' => $outcome->reversalId],
        default => ['result' => 'created', 'reversal' => $outcome->reversalId],
    };
} catch (IdempotencyConflict) {
    $result = ['result' => 'conflict'];
}

echo json_encode($result);
