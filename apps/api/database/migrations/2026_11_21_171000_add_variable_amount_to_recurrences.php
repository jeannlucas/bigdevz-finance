<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const MAX = '99999999999999';

    public function up(): void
    {
        Schema::table('recurrences', function (Blueprint $table) {
            $table->boolean('is_variable')->default(false)->after('payee');
            $table->bigInteger('estimated_amount_cents')->nullable()->after('amount_cents');
        });

        DB::statement('ALTER TABLE recurrences ALTER COLUMN amount_cents DROP NOT NULL');

        DB::statement('ALTER TABLE recurrences DROP CONSTRAINT IF EXISTS recurrences_amount_cents_check');
        DB::statement('ALTER TABLE recurrences ADD CONSTRAINT recurrences_amount_cents_check CHECK (
            (is_variable = false AND amount_cents > 0 AND amount_cents <= '.self::MAX.')
            OR (is_variable = true AND (amount_cents IS NULL OR (amount_cents > 0 AND amount_cents <= '.self::MAX.')))
        )');
        DB::statement('ALTER TABLE recurrences ADD CONSTRAINT recurrences_estimated_amount_check CHECK (
            estimated_amount_cents IS NULL OR (estimated_amount_cents > 0 AND estimated_amount_cents <= '.self::MAX.')
        )');

        Schema::table('payables', function (Blueprint $table) {
            $table->bigInteger('estimated_amount_cents')->nullable()->after('amount_cents');
        });

        DB::statement('ALTER TABLE payables DROP CONSTRAINT IF EXISTS payables_kind_check');
        DB::statement("ALTER TABLE payables ADD CONSTRAINT payables_kind_check CHECK (
            (kind = 'single' AND plan_id IS NULL AND recurrence_id IS NULL AND card_id IS NULL AND cycle IS NULL AND amount_cents IS NOT NULL)
            OR (kind = 'installment' AND plan_id IS NOT NULL AND installment_number IS NOT NULL AND recurrence_id IS NULL AND card_id IS NULL AND amount_cents IS NOT NULL)
            OR (kind = 'recurring' AND recurrence_id IS NOT NULL AND cycle IS NOT NULL AND plan_id IS NULL AND card_id IS NULL)
            OR (kind = 'card_bill' AND card_id IS NOT NULL AND cycle IS NOT NULL AND plan_id IS NULL AND recurrence_id IS NULL)
        )");
        DB::statement('ALTER TABLE payables ADD CONSTRAINT payables_estimated_amount_check CHECK (
            estimated_amount_cents IS NULL OR (estimated_amount_cents > 0 AND estimated_amount_cents <= '.self::MAX.')
        )');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE payables DROP CONSTRAINT IF EXISTS payables_estimated_amount_check');
        DB::statement('ALTER TABLE payables DROP CONSTRAINT IF EXISTS payables_kind_check');
        DB::statement("ALTER TABLE payables ADD CONSTRAINT payables_kind_check CHECK (
            (kind = 'single' AND plan_id IS NULL AND recurrence_id IS NULL AND card_id IS NULL AND cycle IS NULL AND amount_cents IS NOT NULL)
            OR (kind = 'installment' AND plan_id IS NOT NULL AND installment_number IS NOT NULL AND recurrence_id IS NULL AND card_id IS NULL AND amount_cents IS NOT NULL)
            OR (kind = 'recurring' AND recurrence_id IS NOT NULL AND cycle IS NOT NULL AND plan_id IS NULL AND card_id IS NULL AND amount_cents IS NOT NULL)
            OR (kind = 'card_bill' AND card_id IS NOT NULL AND cycle IS NOT NULL AND plan_id IS NULL AND recurrence_id IS NULL)
        )");

        Schema::table('payables', function (Blueprint $table) {
            $table->dropColumn('estimated_amount_cents');
        });

        DB::statement('ALTER TABLE recurrences DROP CONSTRAINT IF EXISTS recurrences_estimated_amount_check');
        DB::statement('ALTER TABLE recurrences DROP CONSTRAINT IF EXISTS recurrences_amount_cents_check');
        DB::statement('ALTER TABLE recurrences ADD CONSTRAINT recurrences_amount_cents_check CHECK (amount_cents > 0 AND amount_cents <= '.self::MAX.')');
        DB::statement('ALTER TABLE recurrences ALTER COLUMN amount_cents SET NOT NULL');

        Schema::table('recurrences', function (Blueprint $table) {
            $table->dropColumn(['is_variable', 'estimated_amount_cents']);
        });
    }
};
