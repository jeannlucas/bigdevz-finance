<?php

// Processo independente para os testes de concorrência de contas: arquiva ou
// corrige a abertura pelo caso de uso real, em conexão própria.

use App\Actions\Accounts\AdjustAccountOpening;
use App\Actions\Accounts\ArchiveAccount;
use App\Models\Space;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;

require __DIR__.'/../../vendor/autoload.php';
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

[, $operation, $userId, $spaceId, $accountId] = $argv;
$space = Space::query()->findOrFail($spaceId);

if ($operation === 'archive') {
    app(ArchiveAccount::class)->handle($space, (int) $accountId, true);
    $result = ['result' => 'archived'];
} else {
    [, , , , , $cents, $date, $key] = $argv;
    $outcome = app(AdjustAccountOpening::class)->handle(User::query()->findOrFail($userId), $space, (int) $accountId, (int) $cents, $date, 'Disputa', $key);
    $result = $outcome->rejected() ? ['result' => 'rejected', 'errors' => $outcome->errors] : ['result' => 'created'];
}

echo json_encode($result);
