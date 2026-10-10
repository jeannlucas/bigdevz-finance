<?php

// Processo independente para os testes de concorrência do A pagar: paga,
// estorna ou corrige pelo caso de uso real, em conexão própria.

use App\Actions\Payables\CreatePayable;
use App\Actions\Payables\PayPayable;
use App\Actions\Payables\ReversePayment;
use App\Actions\Receivables\IdempotencyConflict;
use App\Actions\Receivables\IdempotentOperations;
use App\Models\Space;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;

require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

[, $operation, $userId, $spaceId, $targetId, $key] = $argv;
$user = User::query()->findOrFail($userId);
$space = Space::query()->findOrFail($spaceId);

try {
    $outcome = match ($operation) {
        'create' => (static function () use ($user, $space, $key, $argv) {
            $data = json_decode($argv[6], true);
            $operation = $data['kind'] === 'recurring' ? IdempotentOperations::RECURRENCE : IdempotentOperations::PAYABLE;
            $fingerprint = CreatePayable::fingerprint($operation, $space, $data);
            $create = app(CreatePayable::class);

            return $data['kind'] === 'recurring'
                ? $create->recurrence($user, $space, $data, $key, $fingerprint)
                : $create->installments($user, $space, $data, $key, $fingerprint);
        })(),
        'pay' => app(PayPayable::class)->handle($user, $space, (int) $targetId, (int) $argv[6], (int) $argv[7], $argv[8], $key),
        'correct' => app(ReversePayment::class)->handle($user, $space, (int) $targetId, 'Disputa', $key, [
            'account_id' => (int) $argv[6], 'amount_cents' => (int) $argv[7], 'paid_on' => $argv[8],
        ]),
        default => app(ReversePayment::class)->handle($user, $space, (int) $targetId, 'Disputa', $key),
    };
    $result = match (true) {
        $outcome->rejected() => ['result' => 'rejected', 'errors' => $outcome->errors],
        $outcome->replayed => ['result' => 'replayed'],
        default => ['result' => 'created'],
    };
} catch (IdempotencyConflict) {
    $result = ['result' => 'conflict'];
}

echo json_encode($result);
