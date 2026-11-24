<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const REFS = 'receipt_id, receipt_reversal_id, account_opening_adjustment_id, payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id, loan_id, transfer_reversal_id';

    private const OPERATIONS = "'receipt', 'reversal', 'correction', 'opening_adjustment', 'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction', 'transfer', 'loan', 'transfer_reversal'";

    public function up(): void
    {
        Schema::create('wise_currencies', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id');
            $table->foreignId('account_id');
            $table->char('currency', 3);
            $table->bigInteger('opening_units');
            $table->timestamps();
            $table->foreign(['account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
            $table->unique(['account_id', 'currency']);
            $table->unique(['id', 'space_id']);
        });
        DB::statement("ALTER TABLE wise_currencies ADD CHECK (currency ~ '^[A-Z]{3}$' AND currency <> 'BRL' AND opening_units BETWEEN 0 AND 99999999999999)");

        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->foreignId('wise_currency_id')->nullable();
            $table->foreign(['wise_currency_id', 'space_id'])->references(['id', 'space_id'])->on('wise_currencies')->restrictOnDelete();
        });
        $this->replaceConstraints(self::REFS.', wise_currency_id', self::OPERATIONS.", 'wise_currency'");
    }

    public function down(): void
    {
        $this->replaceConstraints(self::REFS, self::OPERATIONS);
        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->dropForeign(['wise_currency_id', 'space_id']);
            $table->dropColumn('wise_currency_id');
        });
        Schema::dropIfExists('wise_currencies');
    }

    private function replaceConstraints(string $refs, string $operations): void
    {
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check, DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN ($operations))");
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls($refs) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls($refs) = 1)
        )");
    }
};
