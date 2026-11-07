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
        Schema::create('loans', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->string('kind', 10);
            $table->string('title', 120);
            $table->string('counterparty', 120);
            $table->bigInteger('principal_cents');
            $table->bigInteger('total_cents');
            $table->unsignedSmallInteger('installment_count');
            $table->date('first_due_date');
            $table->unsignedBigInteger('disbursement_account_id')->nullable();
            $table->date('disbursed_at')->nullable();
            $table->string('status', 20)->default('active');
            $table->string('notes', 500)->nullable();
            $table->unsignedBigInteger('payable_plan_id')->nullable();
            $table->unsignedBigInteger('agreement_id')->nullable();
            $table->timestampsTz();

            $table->unique(['id', 'space_id']);
            $table->foreign(['disbursement_account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
            $table->foreign(['payable_plan_id', 'space_id'])->references(['id', 'space_id'])->on('payable_plans')->restrictOnDelete();
            $table->foreign(['agreement_id', 'space_id'])->references(['id', 'space_id'])->on('agreements')->restrictOnDelete();
        });

        DB::statement("ALTER TABLE loans ADD CONSTRAINT loans_kind_check CHECK (kind IN ('taken', 'granted'))");
        DB::statement('ALTER TABLE loans ADD CONSTRAINT loans_principal_check CHECK (principal_cents > 0 AND principal_cents <= '.self::MAX_CENTS.')');
        DB::statement('ALTER TABLE loans ADD CONSTRAINT loans_total_check CHECK (total_cents >= principal_cents AND total_cents <= '.self::MAX_CENTS.')');
        DB::statement('ALTER TABLE loans ADD CONSTRAINT loans_installment_count_check CHECK (installment_count BETWEEN 1 AND 1200)');
        DB::statement("ALTER TABLE loans ADD CONSTRAINT loans_status_check CHECK (status IN ('active', 'settled', 'cancelled'))");
        DB::statement('ALTER TABLE loans ADD CONSTRAINT loans_disbursement_pair_check CHECK ((disbursement_account_id IS NULL) = (disbursed_at IS NULL))');
        DB::statement('ALTER TABLE loans ADD CONSTRAINT loans_disbursement_date_check CHECK (disbursed_at IS NULL OR disbursed_at <= first_due_date)');
        DB::statement("ALTER TABLE loans ADD CONSTRAINT loans_integration_check CHECK (
            (kind = 'taken' AND payable_plan_id IS NOT NULL AND agreement_id IS NULL)
            OR (kind = 'granted' AND agreement_id IS NOT NULL AND payable_plan_id IS NULL)
        )");

        Schema::table('account_movements', function (Blueprint $table) {
            $table->foreignId('loan_disbursement_id')->nullable()->constrained('loans')->restrictOnDelete();
            $table->unique(['loan_disbursement_id', 'account_id']);
        });

        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK (
            num_nonnulls(receipt_id, receipt_reversal_id, payment_id, payment_reversal_id, transfer_id, loan_disbursement_id) = 1
            AND (receipt_id IS NULL OR amount_cents > 0)
            AND (receipt_reversal_id IS NULL OR amount_cents < 0)
            AND (payment_id IS NULL OR amount_cents < 0)
            AND (payment_reversal_id IS NULL OR amount_cents > 0)
            AND (transfer_id IS NULL OR amount_cents <> 0)
            AND (loan_disbursement_id IS NULL OR amount_cents <> 0)
        )');

        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->foreignId('loan_id')->nullable()->constrained('loans')->restrictOnDelete();
        });

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN (
            'receipt', 'reversal', 'correction', 'opening_adjustment',
            'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction',
            'transfer', 'loan'
        ))");

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id, loan_id) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id, loan_id) = 1)
        )");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id, transfer_id) = 1)
        )");

        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN (
            'receipt', 'reversal', 'correction', 'opening_adjustment',
            'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction',
            'transfer'
        ))");

        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->dropConstrainedForeignId('loan_id');
        });

        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        Schema::table('account_movements', function (Blueprint $table) {
            $table->dropUnique(['loan_disbursement_id', 'account_id']);
            $table->dropConstrainedForeignId('loan_disbursement_id');
        });

        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK (
            num_nonnulls(receipt_id, receipt_reversal_id, payment_id, payment_reversal_id, transfer_id) = 1
            AND (receipt_id IS NULL OR amount_cents > 0)
            AND (receipt_reversal_id IS NULL OR amount_cents < 0)
            AND (payment_id IS NULL OR amount_cents < 0)
            AND (payment_reversal_id IS NULL OR amount_cents > 0)
            AND (transfer_id IS NULL OR amount_cents <> 0)
        )');

        Schema::dropIfExists('loans');
    }
};
