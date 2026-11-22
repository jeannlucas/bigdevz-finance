<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('alert_states', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->restrictOnDelete();
            $table->foreignId('space_id')->constrained()->restrictOnDelete();
            $table->string('alert_key', 100);
            $table->timestampTz('read_at')->nullable();
            $table->timestampTz('dismissed_at')->nullable();
            $table->timestampsTz();

            $table->unique(['user_id', 'space_id', 'alert_key']);
            $table->index(['space_id', 'user_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('alert_states');
    }
};
