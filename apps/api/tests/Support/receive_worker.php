<?php

// Processo independente usado pelo teste de concorrência: cada execução abre
// sua própria conexão PostgreSQL e chama o caso de uso real de recebimento.

use App\Actions\Receivables\IdempotencyConflict;
use App\Actions\Receivables\ReceiveInstallment;
use App\Models\Space;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Validation\ValidationException;

require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

[, $userId, $spaceId, $installmentId, $accountId, $cents, $date, $key] = $argv;

try {
    $outcome = app(ReceiveInstallment::class)->handle(
        User::query()->findOrFail($userId), Space::query()->findOrFail($spaceId),
        (int) $installmentId, (int) $accountId, (int) $cents, $date, $key,
    );
    $result = ['result' => $outcome->created ? 'created' : 'replayed', 'receipt' => $outcome->receipt->id];
} catch (ValidationException $error) {
    $result = ['result' => 'rejected', 'errors' => $error->errors()];
} catch (IdempotencyConflict) {
    $result = ['result' => 'conflict'];
}

echo json_encode($result);
