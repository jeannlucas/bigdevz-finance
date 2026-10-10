<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Arquivamento de contas e correção auditada do saldo inicial.
 *
 * Somente estrutura: nenhuma linha existente é alterada. Arquivar marca a
 * conta (archived_at), sem tocar em dinheiro. A correção de abertura grava o
 * antes e o depois em account_opening_adjustments e atualiza a abertura da
 * conta na mesma transação; movimentações nunca são alteradas.
 */
return new class extends Migration
{
    private const MAX_CENTS = 99999999999999;

    public function up(): void
    {
        Schema::table('accounts', function (Blueprint $table) {
            $table->timestampTz('archived_at')->nullable();
        });

        Schema::create('account_opening_adjustments', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('space_id');
            $table->unsignedBigInteger('account_id');
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->bigInteger('previous_opening_balance_cents');
            $table->date('previous_opening_balance_date');
            $table->bigInteger('new_opening_balance_cents');
            $table->date('new_opening_balance_date');
            $table->string('reason', 500);
            $table->timestampsTz();
            $table->foreign(['account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
            $table->index(['account_id', 'id']);
        });
        foreach (['previous_opening_balance_cents', 'new_opening_balance_cents'] as $column) {
            DB::statement("ALTER TABLE account_opening_adjustments ADD CONSTRAINT account_opening_adjustments_{$column}_check CHECK ({$column} >= 0 AND {$column} <= ".self::MAX_CENTS.')');
        }
        DB::statement('ALTER TABLE account_opening_adjustments ADD CONSTRAINT account_opening_adjustments_reason_check CHECK (length(btrim(reason)) >= 3)');
        DB::statement('ALTER TABLE account_opening_adjustments ADD CONSTRAINT account_opening_adjustments_change_check CHECK ('
            .'previous_opening_balance_cents <> new_opening_balance_cents OR previous_opening_balance_date <> new_opening_balance_date)');

        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->foreignId('account_opening_adjustment_id')->nullable()->constrained()->restrictOnDelete();
        });
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN ('receipt', 'reversal', 'correction', 'opening_adjustment'))");
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement('ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK ('
            ."(status = 'rejected' AND errors IS NOT NULL AND receipt_id IS NULL AND receipt_reversal_id IS NULL AND account_opening_adjustment_id IS NULL)"
            ." OR (status = 'completed' AND errors IS NULL AND (receipt_id IS NOT NULL OR receipt_reversal_id IS NOT NULL OR account_opening_adjustment_id IS NOT NULL)))");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_status_check');
        DB::statement('ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK ('
            ."(status = 'rejected' AND errors IS NOT NULL AND receipt_id IS NULL AND receipt_reversal_id IS NULL)"
            ." OR (status = 'completed' AND errors IS NULL AND (receipt_id IS NOT NULL OR receipt_reversal_id IS NOT NULL)))");
        DB::statement('ALTER TABLE idempotency_keys DROP CONSTRAINT idempotency_keys_operation_check');
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN ('receipt', 'reversal', 'correction'))");
        Schema::table('idempotency_keys', function (Blueprint $table) {
            $table->dropConstrainedForeignId('account_opening_adjustment_id');
        });
        Schema::dropIfExists('account_opening_adjustments');
        Schema::table('accounts', function (Blueprint $table) {
            $table->dropColumn('archived_at');
        });
    }
};
