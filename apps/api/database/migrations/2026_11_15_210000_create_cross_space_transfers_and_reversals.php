<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Suporte a espaço de destino em transfers
        Schema::table('transfers', function (Blueprint $table) {
            $table->unsignedBigInteger('destination_space_id')->nullable()->after('space_id');
        });

        DB::statement('UPDATE transfers SET destination_space_id = space_id WHERE destination_space_id IS NULL');

        Schema::table('transfers', function (Blueprint $table) {
            $table->unsignedBigInteger('destination_space_id')->nullable(false)->change();
            $table->foreign('destination_space_id')->references('id')->on('spaces')->restrictOnDelete();
            $table->dropForeign('transfers_destination_account_id_space_id_foreign');
            $table->foreign(['destination_account_id', 'destination_space_id'])
                ->references(['id', 'space_id'])
                ->on('accounts')
                ->restrictOnDelete();
            $table->index(['destination_space_id', 'transferred_at']);
        });

        // 2. Tabela de estornos coordenados de transferências
        Schema::create('transfer_reversals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('transfer_id')->unique()->constrained('transfers')->restrictOnDelete();
            $table->foreignId('space_id')->constrained('spaces')->restrictOnDelete();
            $table->foreignId('destination_space_id')->constrained('spaces')->restrictOnDelete();
            $table->unsignedBigInteger('source_account_id');
            $table->unsignedBigInteger('destination_account_id');
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->string('reason', 500);
            $table->timestampsTz();

            $table->foreign(['source_account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
            $table->foreign(['destination_account_id', 'destination_space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
        });

        DB::statement('ALTER TABLE transfer_reversals ADD CONSTRAINT transfer_reversals_reason_check CHECK (length(btrim(reason)) >= 3)');

        // 3. Suporte a transfer_reversal em account_movements preservando loan_disbursement_id
        Schema::table('account_movements', function (Blueprint $table) {
            $table->foreignId('transfer_reversal_id')->nullable()->constrained('transfer_reversals')->restrictOnDelete();
            $table->unique(['transfer_reversal_id', 'account_id']);
        });

        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK (
            num_nonnulls(receipt_id, receipt_reversal_id, payment_id, payment_reversal_id, transfer_id, loan_disbursement_id, transfer_reversal_id) = 1
            AND (receipt_id IS NULL OR amount_cents > 0)
            AND (receipt_reversal_id IS NULL OR amount_cents < 0)
            AND (payment_id IS NULL OR amount_cents < 0)
            AND (payment_reversal_id IS NULL OR amount_cents > 0)
            AND (transfer_id IS NULL OR amount_cents <> 0)
            AND (loan_disbursement_id IS NULL OR amount_cents <> 0)
            AND (transfer_reversal_id IS NULL OR amount_cents <> 0)
        )');

        // 4. Suporte a transfer_reversal em idempotency_keys preservando loan_id
        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->foreignId('transfer_reversal_id')->nullable()->constrained('transfer_reversals')->restrictOnDelete();
        });

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN (
            'receipt', 'reversal', 'correction', 'opening_adjustment',
            'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction',
            'transfer', 'loan', 'transfer_reversal'
        ))");

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id, loan_id, transfer_reversal_id) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id, loan_id, transfer_reversal_id) = 1)
        )");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id, loan_id) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id, loan_id) = 1)
        )");

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN (
            'receipt', 'reversal', 'correction', 'opening_adjustment',
            'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction',
            'transfer', 'loan'
        ))");

        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->dropConstrainedForeignId('transfer_reversal_id');
        });

        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        Schema::table('account_movements', function (Blueprint $table) {
            $table->dropUnique(['transfer_reversal_id', 'account_id']);
            $table->dropConstrainedForeignId('transfer_reversal_id');
        });
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK (
            num_nonnulls(receipt_id, receipt_reversal_id, payment_id, payment_reversal_id, transfer_id, loan_disbursement_id) = 1
            AND (receipt_id IS NULL OR amount_cents > 0)
            AND (receipt_reversal_id IS NULL OR amount_cents < 0)
            AND (payment_id IS NULL OR amount_cents < 0)
            AND (payment_reversal_id IS NULL OR amount_cents > 0)
            AND (transfer_id IS NULL OR amount_cents <> 0)
            AND (loan_disbursement_id IS NULL OR amount_cents <> 0)
        )');

        Schema::dropIfExists('transfer_reversals');

        Schema::table('transfers', function (Blueprint $table) {
            $table->dropIndex(['destination_space_id', 'transferred_at']);
            $table->dropForeign(['destination_account_id', 'destination_space_id']);
            $table->foreign(['destination_account_id', 'space_id'])
                ->references(['id', 'space_id'])
                ->on('accounts')
                ->restrictOnDelete();
            $table->dropConstrainedForeignId('destination_space_id');
        });
    }
};
