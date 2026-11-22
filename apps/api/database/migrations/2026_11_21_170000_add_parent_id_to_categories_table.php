<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('categories', function (Blueprint $table) {
            $table->unsignedBigInteger('parent_id')->nullable()->after('space_id');
            $table->foreign(['parent_id', 'space_id'])->references(['id', 'space_id'])->on('categories')->restrictOnDelete();
            $table->index(['space_id', 'parent_id']);
        });
    }

    public function down(): void
    {
        Schema::table('categories', function (Blueprint $table) {
            $table->dropForeign(['parent_id', 'space_id']);
            $table->dropIndex(['space_id', 'parent_id']);
            $table->dropColumn('parent_id');
        });
    }
};
