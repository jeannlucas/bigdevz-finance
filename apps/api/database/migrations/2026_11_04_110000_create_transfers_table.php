<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const MAX_CENTS = 99999999999999;

    public function up(): void
    {
        Schema::create('transfers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->unsignedBigInteger('source_account_id');
            $table->unsignedBigInteger('destination_account_id');
            $table->bigInteger('amount_cents');
            $table->date('transferred_at');
            $table->string('notes', 500)->nullable();
            $table->timestampsTz();

            $table->unique(['id', 'space_id']);
            $table->foreign(['source_account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
            $table->foreign(['destination_account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
        });

        DB::statement('ALTER TABLE transfers ADD CONSTRAINT transfers_distinct_accounts_check CHECK (source_account_id <> destination_account_id)');
        DB::statement('ALTER TABLE transfers ADD CONSTRAINT transfers_amount_check CHECK (amount_cents > 0 AND amount_cents <= '.self::MAX_CENTS.')');

        Schema::table('account_movements', function (Blueprint $table) {
            $table->foreignId('transfer_id')->nullable()->constrained('transfers')->restrictOnDelete();
            $table->unique(['transfer_id', 'account_id']);
        });

        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK (
            num_nonnulls(receipt_id, receipt_reversal_id, payment_id, payment_reversal_id, transfer_id) = 1
            AND (receipt_id IS NULL OR amount_cents > 0)
            AND (receipt_reversal_id IS NULL OR amount_cents < 0)
            AND (payment_id IS NULL OR amount_cents < 0)
            AND (payment_reversal_id IS NULL OR amount_cents > 0)
            AND (transfer_id IS NULL OR amount_cents <> 0)
        )');

        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->foreignId('transfer_id')->nullable()->constrained('transfers')->restrictOnDelete();
        });

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN (
            'receipt', 'reversal', 'correction', 'opening_adjustment',
            'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction', 'transfer'
        ))");

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id) = 1)
        )");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id) = 1)
        )");

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN (
            'receipt', 'reversal', 'correction', 'opening_adjustment',
            'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction'
        ))");

        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->dropConstrainedForeignId('transfer_id');
        });

        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        Schema::table('account_movements', function (Blueprint $table) {
            $table->dropUnique(['transfer_id', 'account_id']);
            $table->dropConstrainedForeignId('transfer_id');
        });

        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK (
            num_nonnulls(receipt_id, receipt_reversal_id, payment_id, payment_reversal_id) = 1
            AND (receipt_id IS NULL OR amount_cents > 0)
            AND (receipt_reversal_id IS NULL OR amount_cents < 0)
            AND (payment_id IS NULL OR amount_cents < 0)
            AND (payment_reversal_id IS NULL OR amount_cents > 0)
        )');

        Schema::dropIfExists('transfers');
    }
};
