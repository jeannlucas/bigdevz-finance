<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Tabela de associação space_users com perfil RBAC
        Schema::create('space_users', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('role', 20)->default('administrador');
            $table->timestampsTz();
            $table->unique(['space_id', 'user_id']);
        });

        DB::statement("ALTER TABLE space_users ADD CONSTRAINT space_users_role_check CHECK (role IN ('administrador', 'financeiro', 'operador', 'contador'))");

        // Migração não-destrutiva dos espaços existentes (todos os criadores viram administradores)
        DB::statement("
            INSERT INTO space_users (space_id, user_id, role, created_at, updated_at)
            SELECT id, user_id, 'administrador', created_at, updated_at
            FROM spaces
            ON CONFLICT (space_id, user_id) DO NOTHING
        ");

        // 2. Coluna closed_until na tabela spaces
        Schema::table('spaces', function (Blueprint $table) {
            $table->date('closed_until')->nullable();
        });

        // 3. Tabela de auditoria para fechamento e reabertura de período contábil
        Schema::create('space_closing_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('action', 15);
            $table->date('closed_until')->nullable();
            $table->date('previous_closed_until')->nullable();
            $table->text('reason')->nullable();
            $table->timestampsTz();
        });

        DB::statement("ALTER TABLE space_closing_logs ADD CONSTRAINT space_closing_logs_action_check CHECK (action IN ('closed', 'reopened'))");

        // 4. Expandir tamanho das colunas e subjects suportados em obligation_changes
        DB::statement('ALTER TABLE obligation_changes ALTER COLUMN subject TYPE VARCHAR(30)');
        DB::statement('ALTER TABLE obligation_changes ALTER COLUMN action TYPE VARCHAR(30)');
        DB::statement('ALTER TABLE obligation_changes DROP CONSTRAINT IF EXISTS obligation_changes_subject_check');
        DB::statement("ALTER TABLE obligation_changes ADD CONSTRAINT obligation_changes_subject_check CHECK (subject IN ('payable', 'recurrence', 'card', 'agreement', 'receipt', 'payment', 'transfer', 'account', 'period_closing'))");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE obligation_changes DROP CONSTRAINT IF EXISTS obligation_changes_subject_check');
        DB::statement("ALTER TABLE obligation_changes ADD CONSTRAINT obligation_changes_subject_check CHECK (subject IN ('payable', 'recurrence', 'card', 'agreement'))");

        Schema::dropIfExists('space_closing_logs');

        Schema::table('spaces', function (Blueprint $table) {
            $table->dropColumn('closed_until');
        });

        Schema::dropIfExists('space_users');
    }
};
