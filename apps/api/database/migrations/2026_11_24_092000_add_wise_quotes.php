<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('wise_currencies', function (Blueprint $table) {
            $table->string('brl_rate', 24)->nullable();
            $table->date('quoted_on')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('wise_currencies', function (Blueprint $table) {
            $table->dropColumn(['brl_rate', 'quoted_on']);
        });
    }
};
