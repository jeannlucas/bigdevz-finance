<?php

namespace App\Actions\Receivables;

use App\Models\Receipt;

final class ReceiptOutcome
{
    public function __construct(
        public readonly Receipt $receipt,
        public readonly bool $created,
    ) {}
}
