<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('reconciled_transactions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained('spaces')->cascadeOnDelete();
            $table->foreignId('account_id')->constrained('accounts')->cascadeOnDelete();
            $table->string('fitid', 120);
            $table->bigInteger('amount_cents');
            $table->string('type', 20); // 'credit', 'debit'
            $table->date('posted_at');
            $table->string('memo', 255)->nullable();
            $table->string('matched_type', 30); // 'payable', 'installment', 'movement', 'ignored'
            $table->bigInteger('matched_id')->nullable();
            $table->foreignId('account_movement_id')->nullable()->constrained('account_movements')->nullOnDelete();
            $table->timestamps();

            $table->unique(['space_id', 'account_id', 'fitid']);
            $table->index(['space_id', 'account_id', 'posted_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('reconciled_transactions');
    }
};
