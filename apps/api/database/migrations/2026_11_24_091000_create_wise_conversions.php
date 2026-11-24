<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const REFS = 'receipt_id, receipt_reversal_id, account_opening_adjustment_id, payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id, loan_id, transfer_reversal_id, wise_currency_id';

    private const OPERATIONS = "'receipt', 'reversal', 'correction', 'opening_adjustment', 'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction', 'transfer', 'loan', 'transfer_reversal', 'wise_currency'";

    private const SOURCES = 'receipt_id, receipt_reversal_id, payment_id, payment_reversal_id, transfer_id, loan_disbursement_id, transfer_reversal_id';

    public function up(): void
    {
        Schema::create('wise_conversions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('account_id');
            $table->foreignId('space_id');
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->date('effective_date');
            $table->jsonb('details');
            $table->foreignId('reverses_id')->nullable()->unique();
            $table->foreign(['account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
            $table->unique(['id', 'space_id']);
            $table->unique(['id', 'account_id', 'space_id']);
            $table->unique(['id', 'account_id']);
            $table->foreign(['reverses_id', 'account_id', 'space_id'])->references(['id', 'account_id', 'space_id'])->on('wise_conversions')->restrictOnDelete();
            $table->timestamps();
        });
        Schema::create('wise_currency_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id');
            $table->foreignId('wise_currency_id');
            $table->foreignId('wise_conversion_id');
            $table->bigInteger('units');
            $table->foreign(['wise_currency_id', 'space_id'])->references(['id', 'space_id'])->on('wise_currencies')->restrictOnDelete();
            $table->foreign(['wise_conversion_id', 'space_id'])->references(['id', 'space_id'])->on('wise_conversions')->restrictOnDelete();
            $table->unique(['wise_currency_id', 'wise_conversion_id']);
        });
        DB::statement('ALTER TABLE wise_currency_movements ADD CHECK (units <> 0 AND units BETWEEN -99999999999999 AND 99999999999999)');
        Schema::table('account_movements', function (Blueprint $table) {
            $table->foreignId('wise_conversion_id')->nullable()->unique();
            $table->foreign(['wise_conversion_id', 'account_id'])->references(['id', 'account_id'])->on('wise_conversions')->restrictOnDelete();
        });
        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->foreignId('wise_conversion_id')->nullable();
            $table->foreign(['wise_conversion_id', 'space_id'])->references(['id', 'space_id'])->on('wise_conversions')->restrictOnDelete();
        });
        $this->constraints(self::SOURCES.', wise_conversion_id', self::REFS.', wise_conversion_id', self::OPERATIONS.", 'wise_conversion', 'wise_reversal'");
    }

    public function down(): void
    {
        $this->constraints(self::SOURCES, self::REFS, self::OPERATIONS);
        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->dropForeign(['wise_conversion_id', 'space_id']);
            $table->dropColumn('wise_conversion_id');
        });
        Schema::table('account_movements', function (Blueprint $table) {
            $table->dropForeign(['wise_conversion_id', 'account_id']);
            $table->dropColumn('wise_conversion_id');
        });
        Schema::dropIfExists('wise_currency_movements');
        Schema::dropIfExists('wise_conversions');
    }

    private function constraints(string $sources, string $refs, string $operations): void
    {
        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        DB::statement("ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK (
            num_nonnulls($sources) = 1
            AND (receipt_id IS NULL OR amount_cents > 0)
            AND (receipt_reversal_id IS NULL OR amount_cents < 0)
            AND (payment_id IS NULL OR amount_cents < 0)
            AND (payment_reversal_id IS NULL OR amount_cents > 0)
        )");
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check, DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN ($operations))");
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls($refs) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls($refs) = 1)
        )");
    }
};
