<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('categories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('space_id')->constrained()->cascadeOnDelete();
            $table->string('name', 60);
            $table->string('icon', 50)->default('category');
            $table->string('color', 10)->default('#1E5BB8');
            $table->string('type', 10);
            $table->boolean('is_default')->default(false);
            $table->timestampsTz();

            $table->unique(['id', 'space_id']);
            $table->unique(['space_id', 'type', 'name']);
            $table->index(['space_id', 'type']);
        });

        DB::statement("ALTER TABLE categories ADD CONSTRAINT categories_type_check CHECK (type IN ('income', 'expense'))");

        Schema::table('agreements', function (Blueprint $table) {
            $table->unsignedBigInteger('category_id')->nullable();
            $table->foreign(['category_id', 'space_id'])->references(['id', 'space_id'])->on('categories')->nullOnDelete();
        });

        Schema::table('payable_plans', function (Blueprint $table) {
            $table->unsignedBigInteger('category_id')->nullable();
            $table->foreign(['category_id', 'space_id'])->references(['id', 'space_id'])->on('categories')->nullOnDelete();
        });

        Schema::table('recurrences', function (Blueprint $table) {
            $table->unsignedBigInteger('category_id')->nullable();
            $table->foreign(['category_id', 'space_id'])->references(['id', 'space_id'])->on('categories')->nullOnDelete();
        });

        Schema::table('payables', function (Blueprint $table) {
            $table->unsignedBigInteger('category_id')->nullable();
            $table->foreign(['category_id', 'space_id'])->references(['id', 'space_id'])->on('categories')->nullOnDelete();
        });

        Schema::table('account_movements', function (Blueprint $table) {
            $table->unsignedBigInteger('category_id')->nullable();
            $table->foreign('category_id')->references('id')->on('categories')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('account_movements', function (Blueprint $table) {
            $table->dropForeign(['category_id']);
            $table->dropColumn('category_id');
        });

        Schema::table('payables', function (Blueprint $table) {
            $table->dropForeign(['category_id', 'space_id']);
            $table->dropColumn('category_id');
        });

        Schema::table('recurrences', function (Blueprint $table) {
            $table->dropForeign(['category_id', 'space_id']);
            $table->dropColumn('category_id');
        });

        Schema::table('payable_plans', function (Blueprint $table) {
            $table->dropForeign(['category_id', 'space_id']);
            $table->dropColumn('category_id');
        });

        Schema::table('agreements', function (Blueprint $table) {
            $table->dropForeign(['category_id', 'space_id']);
            $table->dropColumn('category_id');
        });

        Schema::dropIfExists('categories');
    }
};
