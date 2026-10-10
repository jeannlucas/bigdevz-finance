<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A pagar: obrigações (avulsas, parcelas, ocorrências recorrentes e faturas
 * de cartão pelo total), pagamentos, estornos de pagamento e trilha de
 * alterações. Somente estrutura: nenhuma linha existente é alterada.
 *
 * Obrigação não movimenta conta. Pagamento gera saída (movimentação
 * negativa); estorno gera compensação positiva na data do pagamento original;
 * correção é estorno + substituto. paid_cents é o pago líquido.
 */
return new class extends Migration
{
    private const MAX = 99999999999999;

    public function up(): void
    {
        Schema::create('cards', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->string('name', 80);
            $table->unsignedSmallInteger('due_day');
            $table->date('first_cycle');
            $table->timestampTz('archived_at')->nullable();
            $table->timestampsTz();
            $table->unique(['id', 'space_id']);
        });
        DB::statement('ALTER TABLE cards ADD CONSTRAINT cards_due_day_check CHECK (due_day BETWEEN 1 AND 31)');
        DB::statement("ALTER TABLE cards ADD CONSTRAINT cards_first_cycle_check CHECK (date_trunc('month', first_cycle) = first_cycle)");

        Schema::create('recurrences', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->string('description', 120);
            $table->string('payee', 120)->nullable();
            $table->bigInteger('amount_cents');
            $table->date('start_date');
            $table->unsignedSmallInteger('reference_day');
            $table->date('end_date')->nullable();
            $table->timestampsTz();
            $table->unique(['id', 'space_id']);
        });
        $this->money('recurrences', 'amount_cents', '> 0');
        DB::statement('ALTER TABLE recurrences ADD CONSTRAINT recurrences_reference_day_check CHECK (reference_day BETWEEN 1 AND 31)');
        DB::statement('ALTER TABLE recurrences ADD CONSTRAINT recurrences_end_check CHECK (end_date IS NULL OR end_date >= start_date)');

        Schema::create('payable_plans', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->string('description', 120);
            $table->string('payee', 120)->nullable();
            $table->bigInteger('total_cents');
            $table->unsignedSmallInteger('installment_count');
            $table->date('first_due_date');
            $table->timestampsTz();
            $table->unique(['id', 'space_id']);
        });
        $this->money('payable_plans', 'total_cents', '> 0');
        DB::statement('ALTER TABLE payable_plans ADD CONSTRAINT payable_plans_count_check CHECK (installment_count BETWEEN 1 AND 1200)');

        Schema::create('payables', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('space_id');
            $table->string('kind', 12);
            $table->string('description', 120);
            $table->string('payee', 120)->nullable();
            $table->bigInteger('amount_cents')->nullable();
            $table->bigInteger('paid_cents')->default(0);
            $table->date('due_date');
            $table->unsignedBigInteger('plan_id')->nullable();
            $table->unsignedSmallInteger('installment_number')->nullable();
            $table->unsignedBigInteger('recurrence_id')->nullable();
            $table->unsignedBigInteger('card_id')->nullable();
            $table->date('cycle')->nullable();
            $table->timestampTz('edited_at')->nullable();
            $table->timestampTz('cancelled_at')->nullable();
            $table->string('cancel_reason', 500)->nullable();
            $table->timestampsTz();
            $table->foreign('space_id')->references('id')->on('spaces')->restrictOnDelete();
            $table->unique(['id', 'space_id']);
            $table->unique(['plan_id', 'installment_number']);
            $table->unique(['recurrence_id', 'cycle']);
            $table->unique(['card_id', 'cycle']);
            $table->foreign(['plan_id', 'space_id'])->references(['id', 'space_id'])->on('payable_plans')->restrictOnDelete();
            $table->foreign(['recurrence_id', 'space_id'])->references(['id', 'space_id'])->on('recurrences')->restrictOnDelete();
            $table->foreign(['card_id', 'space_id'])->references(['id', 'space_id'])->on('cards')->restrictOnDelete();
            $table->index(['space_id', 'due_date']);
        });
        DB::statement("ALTER TABLE payables ADD CONSTRAINT payables_kind_check CHECK (
            (kind = 'single' AND plan_id IS NULL AND recurrence_id IS NULL AND card_id IS NULL AND cycle IS NULL AND amount_cents IS NOT NULL)
            OR (kind = 'installment' AND plan_id IS NOT NULL AND installment_number IS NOT NULL AND recurrence_id IS NULL AND card_id IS NULL AND amount_cents IS NOT NULL)
            OR (kind = 'recurring' AND recurrence_id IS NOT NULL AND cycle IS NOT NULL AND plan_id IS NULL AND card_id IS NULL AND amount_cents IS NOT NULL)
            OR (kind = 'card_bill' AND card_id IS NOT NULL AND cycle IS NOT NULL AND plan_id IS NULL AND recurrence_id IS NULL))");
        DB::statement('ALTER TABLE payables ADD CONSTRAINT payables_amount_check CHECK (amount_cents IS NULL OR (amount_cents > 0 AND amount_cents <= '.self::MAX.'))');
        DB::statement('ALTER TABLE payables ADD CONSTRAINT payables_paid_check CHECK (paid_cents >= 0 AND paid_cents <= COALESCE(amount_cents, 0))');
        DB::statement('ALTER TABLE payables ADD CONSTRAINT payables_cancel_check CHECK (cancelled_at IS NULL OR paid_cents = 0)');

        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('space_id');
            $table->unsignedBigInteger('payable_id');
            $table->unsignedBigInteger('account_id');
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->bigInteger('amount_cents');
            $table->date('paid_on');
            $table->timestampsTz();
            $table->unique(['id', 'account_id']);
            $table->unique(['id', 'payable_id', 'space_id']);
            $table->foreign(['payable_id', 'space_id'])->references(['id', 'space_id'])->on('payables')->restrictOnDelete();
            $table->foreign(['account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
        });
        $this->money('payments', 'amount_cents', '> 0');

        Schema::create('payment_reversals', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('space_id');
            $table->unsignedBigInteger('payable_id');
            $table->unsignedBigInteger('payment_id')->unique();
            $table->unsignedBigInteger('account_id');
            $table->unsignedBigInteger('replacement_payment_id')->nullable()->unique();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->string('reason', 500);
            $table->timestampsTz();
            $table->unique(['id', 'account_id']);
            $table->foreign(['payment_id', 'payable_id', 'space_id'])->references(['id', 'payable_id', 'space_id'])->on('payments')->restrictOnDelete();
            $table->foreign(['replacement_payment_id', 'payable_id', 'space_id'])->references(['id', 'payable_id', 'space_id'])->on('payments')->restrictOnDelete();
            $table->foreign(['payment_id', 'account_id'])->references(['id', 'account_id'])->on('payments')->restrictOnDelete();
        });
        DB::statement('ALTER TABLE payment_reversals ADD CONSTRAINT payment_reversals_reason_check CHECK (length(btrim(reason)) >= 3)');
        DB::statement('ALTER TABLE payment_reversals ADD CONSTRAINT payment_reversals_replacement_check CHECK (replacement_payment_id IS NULL OR replacement_payment_id <> payment_id)');

        // Movimentação: entrada de recebimento, saída de pagamento, ou a
        // compensação de um estorno (sinal oposto ao da operação estornada).
        Schema::table('account_movements', function (Blueprint $table) {
            $table->unsignedBigInteger('payment_id')->nullable()->unique();
            $table->unsignedBigInteger('payment_reversal_id')->nullable()->unique();
            $table->foreign(['payment_id', 'account_id'])->references(['id', 'account_id'])->on('payments')->restrictOnDelete();
            $table->foreign(['payment_reversal_id', 'account_id'])->references(['id', 'account_id'])->on('payment_reversals')->restrictOnDelete();
        });
        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK (
            num_nonnulls(receipt_id, receipt_reversal_id, payment_id, payment_reversal_id) = 1
            AND (receipt_id IS NULL OR amount_cents > 0)
            AND (receipt_reversal_id IS NULL OR amount_cents < 0)
            AND (payment_id IS NULL OR amount_cents < 0)
            AND (payment_reversal_id IS NULL OR amount_cents > 0))');

        Schema::create('obligation_changes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->string('subject', 12);
            $table->unsignedBigInteger('subject_id');
            $table->string('action', 12);
            $table->jsonb('before');
            $table->jsonb('after');
            $table->string('reason', 500)->nullable();
            $table->timestampsTz();
            $table->index(['subject', 'subject_id']);
        });
        DB::statement("ALTER TABLE obligation_changes ADD CONSTRAINT obligation_changes_subject_check CHECK (subject IN ('payable', 'recurrence', 'card'))");

        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->foreignId('payable_id')->nullable()->constrained()->restrictOnDelete();
            $table->foreignId('payable_plan_id')->nullable()->constrained()->restrictOnDelete();
            $table->foreignId('recurrence_id')->nullable()->constrained()->restrictOnDelete();
            $table->foreignId('payment_id')->nullable()->constrained()->restrictOnDelete();
            $table->foreignId('payment_reversal_id')->nullable()->constrained()->restrictOnDelete();
        });
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN (
            'receipt', 'reversal', 'correction', 'opening_adjustment',
            'payable', 'recurrence', 'payment', 'payment_reversal', 'payment_correction'))");
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK (
            (status = 'rejected' AND errors IS NOT NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id) = 0)
            OR (status = 'completed' AND errors IS NULL AND num_nonnulls(receipt_id, receipt_reversal_id, account_opening_adjustment_id,
                payable_id, payable_plan_id, recurrence_id, payment_id, payment_reversal_id) = 1))");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement('ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK ('
            ."(status = 'rejected' AND errors IS NOT NULL AND receipt_id IS NULL AND receipt_reversal_id IS NULL AND account_opening_adjustment_id IS NULL)"
            ." OR (status = 'completed' AND errors IS NULL AND (receipt_id IS NOT NULL OR receipt_reversal_id IS NOT NULL OR account_opening_adjustment_id IS NOT NULL)))");
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN ('receipt', 'reversal', 'correction', 'opening_adjustment'))");
        Schema::table('idempotency_keys', function (Blueprint $table) {
            foreach (['payment_reversal_id', 'payment_id', 'recurrence_id', 'payable_plan_id', 'payable_id'] as $column) {
                $table->dropConstrainedForeignId($column);
            }
        });
        Schema::dropIfExists('obligation_changes');
        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        Schema::table('account_movements', function (Blueprint $table) {
            $table->dropForeign(['payment_id', 'account_id']);
            $table->dropForeign(['payment_reversal_id', 'account_id']);
            $table->dropColumn(['payment_id', 'payment_reversal_id']);
        });
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK ('
            .'(receipt_id IS NOT NULL AND receipt_reversal_id IS NULL AND amount_cents > 0)'
            .' OR (receipt_id IS NULL AND receipt_reversal_id IS NOT NULL AND amount_cents < 0))');
        Schema::dropIfExists('payment_reversals');
        Schema::dropIfExists('payments');
        Schema::dropIfExists('payables');
        Schema::dropIfExists('payable_plans');
        Schema::dropIfExists('recurrences');
        Schema::dropIfExists('cards');
    }

    private function money(string $table, string $column, string $min): void
    {
        DB::statement("ALTER TABLE {$table} ADD CONSTRAINT {$table}_{$column}_check CHECK ({$column} {$min} AND {$column} <= ".self::MAX.')');
    }
};
