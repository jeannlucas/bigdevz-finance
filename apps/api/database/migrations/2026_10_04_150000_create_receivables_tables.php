<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Checkpoint 1: espaços PF/PJ, contas, acordos a receber, parcelas e
 * recebimentos. Dinheiro em centavos inteiros (decisão 0002), limitado a
 * 99999999999999 centavos por valor. As invariantes também vivem no banco.
 */
return new class extends Migration
{
    private const MAX_CENTS = 99999999999999;

    public function up(): void
    {
        Schema::create('spaces', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('kind', 2);
            $table->string('name', 80);
            $table->timestampsTz();
            $table->unique(['user_id', 'kind']);
        });
        DB::statement("ALTER TABLE spaces ADD CONSTRAINT spaces_kind_check CHECK (kind IN ('PF', 'PJ'))");

        Schema::create('accounts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->string('name', 80);
            $table->bigInteger('opening_balance_cents');
            $table->date('opening_balance_date');
            $table->timestampsTz();
            $table->unique(['id', 'space_id']);
        });
        $this->checkMoney('accounts', 'opening_balance_cents', allowZero: true);

        Schema::create('agreements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->string('description', 120);
            $table->bigInteger('total_cents');
            $table->unsignedSmallInteger('installment_count');
            $table->date('first_due_date');
            $table->timestampsTz();
            $table->unique(['id', 'space_id']);
        });
        $this->checkMoney('agreements', 'total_cents', allowZero: false);
        DB::statement('ALTER TABLE agreements ADD CONSTRAINT agreements_installment_count_check CHECK (installment_count BETWEEN 1 AND 1200)');

        Schema::create('installments', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('agreement_id');
            $table->unsignedBigInteger('space_id');
            $table->unsignedSmallInteger('number');
            $table->bigInteger('amount_cents');
            $table->bigInteger('received_cents')->default(0);
            $table->date('due_date');
            $table->timestampsTz();
            $table->unique(['agreement_id', 'number']);
            $table->unique(['id', 'space_id']);
            $table->foreign(['agreement_id', 'space_id'])->references(['id', 'space_id'])->on('agreements')->restrictOnDelete();
        });
        $this->checkMoney('installments', 'amount_cents', allowZero: false);
        DB::statement('ALTER TABLE installments ADD CONSTRAINT installments_received_check CHECK (received_cents >= 0 AND received_cents <= amount_cents)');

        Schema::create('receipts', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('space_id');
            $table->unsignedBigInteger('installment_id');
            $table->unsignedBigInteger('account_id');
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->bigInteger('amount_cents');
            $table->date('received_on');
            $table->string('idempotency_key', 100);
            $table->char('request_fingerprint', 64);
            $table->timestampsTz();
            $table->unique(['space_id', 'idempotency_key']);
            $table->unique(['id', 'account_id']);
            $table->foreign(['installment_id', 'space_id'])->references(['id', 'space_id'])->on('installments')->restrictOnDelete();
            $table->foreign(['account_id', 'space_id'])->references(['id', 'space_id'])->on('accounts')->restrictOnDelete();
        });
        $this->checkMoney('receipts', 'amount_cents', allowZero: false);

        Schema::create('account_movements', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('account_id');
            $table->unsignedBigInteger('receipt_id')->unique();
            $table->bigInteger('amount_cents');
            $table->date('effective_date');
            $table->timestampsTz();
            $table->foreign(['receipt_id', 'account_id'])->references(['id', 'account_id'])->on('receipts')->restrictOnDelete();
            $table->index(['account_id', 'effective_date']);
        });
        $this->checkMoney('account_movements', 'amount_cents', allowZero: false);
    }

    public function down(): void
    {
        Schema::dropIfExists('account_movements');
        Schema::dropIfExists('receipts');
        Schema::dropIfExists('installments');
        Schema::dropIfExists('agreements');
        Schema::dropIfExists('accounts');
        Schema::dropIfExists('spaces');
    }

    private function checkMoney(string $table, string $column, bool $allowZero): void
    {
        $min = $allowZero ? '>= 0' : '> 0';
        DB::statement("ALTER TABLE {$table} ADD CONSTRAINT {$table}_{$column}_check CHECK ({$column} {$min} AND {$column} <= ".self::MAX_CENTS.')');
    }
};
