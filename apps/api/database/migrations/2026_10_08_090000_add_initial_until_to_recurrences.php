<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Conjunto inicial aprovado de uma recorrência: o último ciclo revisado pelo
 * usuário no cadastro. Ciclos depois dele vêm da geração automática.
 * Somente estrutura; recorrências existentes ficam com NULL (sem conjunto
 * inicial registrado).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('recurrences', function (Blueprint $table) {
            $table->date('initial_until')->nullable();
        });
        DB::statement("ALTER TABLE recurrences ADD CONSTRAINT recurrences_initial_until_check CHECK (initial_until IS NULL OR (date_trunc('month', initial_until) = initial_until AND initial_until >= date_trunc('month', start_date)))");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE recurrences DROP CONSTRAINT recurrences_initial_until_check');
        Schema::table('recurrences', function (Blueprint $table) {
            $table->dropColumn('initial_until');
        });
    }
};
