<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Estorno e correção de recebimentos, e decisões idempotentes persistidas.
 *
 * Somente estrutura: nenhuma linha existente é alterada. O recebimento
 * original e sua movimentação ficam intactos; o estorno é uma linha própria
 * com uma movimentação compensatória negativa. A correção é um estorno com
 * recebimento substituto na mesma parcela.
 */
return new class extends Migration
{
    private const MAX_CENTS = 99999999999999;

    public function up(): void
    {
        // Recebimentos substitutos não têm chave própria: a identidade da
        // operação é a chave da correção, em idempotency_keys.
        DB::statement('ALTER TABLE receipts ALTER COLUMN idempotency_key DROP NOT NULL');
        DB::statement('ALTER TABLE receipts ALTER COLUMN request_fingerprint DROP NOT NULL');
        DB::statement('ALTER TABLE receipts ADD CONSTRAINT receipts_key_pair_check CHECK ((idempotency_key IS NULL) = (request_fingerprint IS NULL))');
        Schema::table('receipts', function (Blueprint $table) {
            $table->unique(['id', 'installment_id', 'space_id']);
        });

        Schema::create('receipt_reversals', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('space_id');
            $table->unsignedBigInteger('installment_id');
            $table->unsignedBigInteger('receipt_id')->unique();
            $table->unsignedBigInteger('account_id');
            $table->unsignedBigInteger('replacement_receipt_id')->nullable()->unique();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->string('reason', 500);
            $table->timestampsTz();
            $table->unique(['id', 'account_id']);
            // Original e substituto pertencem à mesma parcela e ao mesmo espaço.
            $table->foreign(['receipt_id', 'installment_id', 'space_id'])
                ->references(['id', 'installment_id', 'space_id'])->on('receipts')->restrictOnDelete();
            $table->foreign(['replacement_receipt_id', 'installment_id', 'space_id'])
                ->references(['id', 'installment_id', 'space_id'])->on('receipts')->restrictOnDelete();
            // A compensação sai da mesma conta que recebeu o original.
            $table->foreign(['receipt_id', 'account_id'])->references(['id', 'account_id'])->on('receipts')->restrictOnDelete();
        });
        DB::statement('ALTER TABLE receipt_reversals ADD CONSTRAINT receipt_reversals_reason_check CHECK (length(btrim(reason)) >= 3)');
        DB::statement('ALTER TABLE receipt_reversals ADD CONSTRAINT receipt_reversals_replacement_check CHECK (replacement_receipt_id IS NULL OR replacement_receipt_id <> receipt_id)');

        // Movimentação nasce de um recebimento (entrada) ou de um estorno
        // (saída compensatória), nunca dos dois.
        DB::statement('ALTER TABLE account_movements ALTER COLUMN receipt_id DROP NOT NULL');
        Schema::table('account_movements', function (Blueprint $table) {
            $table->unsignedBigInteger('receipt_reversal_id')->nullable()->unique();
            $table->foreign(['receipt_reversal_id', 'account_id'])
                ->references(['id', 'account_id'])->on('receipt_reversals')->restrictOnDelete();
        });
        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_amount_cents_check');
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_amount_cents_check CHECK ('
            .'amount_cents <> 0 AND amount_cents BETWEEN -'.self::MAX_CENTS.' AND '.self::MAX_CENTS.')');
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_source_check CHECK ('
            .'(receipt_id IS NOT NULL AND receipt_reversal_id IS NULL AND amount_cents > 0)'
            .' OR (receipt_id IS NULL AND receipt_reversal_id IS NOT NULL AND amount_cents < 0))');

        // Decisão final de cada chave idempotente do espaço, inclusive recusas:
        // uma chave recusada continua recusada mesmo que o restante reabra.
        Schema::create('idempotency_keys', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->string('key', 100);
            $table->string('operation', 20);
            $table->char('fingerprint', 64);
            $table->string('status', 10);
            $table->jsonb('errors')->nullable();
            $table->foreignId('receipt_id')->nullable()->constrained()->restrictOnDelete();
            $table->foreignId('receipt_reversal_id')->nullable()->constrained()->restrictOnDelete();
            $table->timestampsTz();
            $table->unique(['space_id', 'key']);
        });
        DB::statement("ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_operation_check CHECK (operation IN ('receipt', 'reversal', 'correction'))");
        DB::statement('ALTER TABLE idempotency_keys ADD CONSTRAINT idempotency_keys_status_check CHECK ('
            ."(status = 'rejected' AND errors IS NOT NULL AND receipt_id IS NULL AND receipt_reversal_id IS NULL)"
            ." OR (status = 'completed' AND errors IS NULL AND (receipt_id IS NOT NULL OR receipt_reversal_id IS NOT NULL)))");
    }

    public function down(): void
    {
        Schema::dropIfExists('idempotency_keys');
        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_source_check');
        DB::statement('ALTER TABLE account_movements DROP CONSTRAINT account_movements_amount_cents_check');
        DB::statement('ALTER TABLE account_movements ADD CONSTRAINT account_movements_amount_cents_check CHECK (amount_cents > 0 AND amount_cents <= '.self::MAX_CENTS.')');
        Schema::table('account_movements', function (Blueprint $table) {
            $table->dropForeign(['receipt_reversal_id', 'account_id']);
            $table->dropColumn('receipt_reversal_id');
        });
        DB::statement('ALTER TABLE account_movements ALTER COLUMN receipt_id SET NOT NULL');
        Schema::dropIfExists('receipt_reversals');
        Schema::table('receipts', function (Blueprint $table) {
            $table->dropUnique(['id', 'installment_id', 'space_id']);
        });
        DB::statement('ALTER TABLE receipts DROP CONSTRAINT receipts_key_pair_check');
        DB::statement('ALTER TABLE receipts ALTER COLUMN request_fingerprint SET NOT NULL');
        DB::statement('ALTER TABLE receipts ALTER COLUMN idempotency_key SET NOT NULL');
    }
};
