<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('agreements', function (Blueprint $table) {
            $table->timestampTz('edited_at')->nullable()->after('category_id');
            $table->timestampTz('cancelled_at')->nullable()->after('edited_at');
            $table->string('cancel_reason', 500)->nullable()->after('cancelled_at');
        });

        DB::statement('ALTER TABLE obligation_changes DROP CONSTRAINT obligation_changes_subject_check');
        DB::statement("ALTER TABLE obligation_changes ADD CONSTRAINT obligation_changes_subject_check CHECK (subject IN ('payable', 'recurrence', 'card', 'agreement'))");
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE obligation_changes DROP CONSTRAINT obligation_changes_subject_check');
        DB::statement("ALTER TABLE obligation_changes ADD CONSTRAINT obligation_changes_subject_check CHECK (subject IN ('payable', 'recurrence', 'card'))");

        Schema::table('agreements', function (Blueprint $table) {
            $table->dropColumn(['edited_at', 'cancelled_at', 'cancel_reason']);
        });
    }
};
