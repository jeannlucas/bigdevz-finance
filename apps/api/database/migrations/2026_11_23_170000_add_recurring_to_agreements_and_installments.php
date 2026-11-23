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
        Schema::table('agreements', function (Blueprint $table) {
            $table->string('kind', 20)->default('installment')->after('space_id');
            $table->boolean('is_variable')->default(false)->after('kind');
            $table->bigInteger('amount_cents')->nullable()->after('description');
            $table->bigInteger('estimated_amount_cents')->nullable()->after('amount_cents');
            $table->date('start_date')->nullable()->after('first_due_date');
            $table->unsignedSmallInteger('reference_day')->nullable()->after('start_date');
            $table->date('end_date')->nullable()->after('reference_day');
            $table->date('initial_until')->nullable()->after('end_date');
            $table->string('idempotency_key', 100)->nullable()->after('cancel_reason');
            $table->unique(['space_id', 'idempotency_key']);
        });

        DB::statement('ALTER TABLE agreements ALTER COLUMN total_cents DROP NOT NULL');
        DB::statement('ALTER TABLE agreements ALTER COLUMN installment_count DROP NOT NULL');
        DB::statement('ALTER TABLE agreements ALTER COLUMN first_due_date DROP NOT NULL');

        DB::statement('ALTER TABLE agreements DROP CONSTRAINT IF EXISTS agreements_total_cents_check');
        DB::statement('ALTER TABLE agreements ADD CONSTRAINT agreements_total_cents_check CHECK (
            total_cents IS NULL OR (total_cents > 0 AND total_cents <= '.self::MAX.')
        )');

        DB::statement('ALTER TABLE agreements DROP CONSTRAINT IF EXISTS agreements_installment_count_check');
        DB::statement('ALTER TABLE agreements ADD CONSTRAINT agreements_installment_count_check CHECK (
            installment_count IS NULL OR (installment_count BETWEEN 1 AND 1200)
        )');

        DB::statement('ALTER TABLE agreements ADD CONSTRAINT agreements_amount_cents_check CHECK (
            amount_cents IS NULL OR (amount_cents > 0 AND amount_cents <= '.self::MAX.')
        )');

        DB::statement('ALTER TABLE agreements ADD CONSTRAINT agreements_estimated_amount_cents_check CHECK (
            estimated_amount_cents IS NULL OR (estimated_amount_cents > 0 AND estimated_amount_cents <= '.self::MAX.')
        )');

        DB::statement('ALTER TABLE agreements ADD CONSTRAINT agreements_reference_day_check CHECK (
            reference_day IS NULL OR (reference_day BETWEEN 1 AND 31)
        )');

        DB::statement("ALTER TABLE agreements ADD CONSTRAINT agreements_kind_check CHECK (
            kind IN ('single', 'installment', 'recurring')
        )");

        Schema::table('installments', function (Blueprint $table) {
            $table->date('cycle')->nullable()->after('due_date');
            $table->bigInteger('estimated_amount_cents')->nullable()->after('amount_cents');
            $table->unique(['agreement_id', 'cycle']);
        });

        DB::statement('ALTER TABLE installments ALTER COLUMN amount_cents DROP NOT NULL');

        DB::statement('ALTER TABLE installments DROP CONSTRAINT IF EXISTS installments_amount_cents_check');
        DB::statement('ALTER TABLE installments ADD CONSTRAINT installments_amount_cents_check CHECK (
            amount_cents IS NULL OR (amount_cents > 0 AND amount_cents <= '.self::MAX.')
        )');

        DB::statement('ALTER TABLE installments DROP CONSTRAINT IF EXISTS installments_received_check');
        DB::statement('ALTER TABLE installments ADD CONSTRAINT installments_received_check CHECK (
            received_cents >= 0 AND (amount_cents IS NULL OR received_cents <= amount_cents)
        )');

        DB::statement('ALTER TABLE installments ADD CONSTRAINT installments_estimated_amount_cents_check CHECK (
            estimated_amount_cents IS NULL OR (estimated_amount_cents > 0 AND estimated_amount_cents <= '.self::MAX.')
        )');
    }

    public function down(): void
    {
        Schema::table('installments', function (Blueprint $table) {
            $table->dropUnique(['agreement_id', 'cycle']);
            $table->dropColumn(['cycle', 'estimated_amount_cents']);
        });

        DB::statement('ALTER TABLE installments DROP CONSTRAINT IF EXISTS installments_estimated_amount_cents_check');
        DB::statement('ALTER TABLE installments DROP CONSTRAINT IF EXISTS installments_received_check');
        DB::statement('ALTER TABLE installments ADD CONSTRAINT installments_received_check CHECK (received_cents >= 0 AND received_cents <= amount_cents)');

        DB::statement('ALTER TABLE installments DROP CONSTRAINT IF EXISTS installments_amount_cents_check');
        DB::statement('ALTER TABLE installments ADD CONSTRAINT installments_amount_cents_check CHECK (amount_cents > 0 AND amount_cents <= '.self::MAX.')');
        DB::statement('ALTER TABLE installments ALTER COLUMN amount_cents SET NOT NULL');

        DB::statement('ALTER TABLE agreements DROP CONSTRAINT IF EXISTS agreements_kind_check');
        DB::statement('ALTER TABLE agreements DROP CONSTRAINT IF EXISTS agreements_reference_day_check');
        DB::statement('ALTER TABLE agreements DROP CONSTRAINT IF EXISTS agreements_estimated_amount_cents_check');
        DB::statement('ALTER TABLE agreements DROP CONSTRAINT IF EXISTS agreements_amount_cents_check');
        DB::statement('ALTER TABLE agreements DROP CONSTRAINT IF EXISTS agreements_installment_count_check');
        DB::statement('ALTER TABLE agreements ADD CONSTRAINT agreements_installment_count_check CHECK (installment_count BETWEEN 1 AND 1200)');
        DB::statement('ALTER TABLE agreements DROP CONSTRAINT IF EXISTS agreements_total_cents_check');
        DB::statement('ALTER TABLE agreements ADD CONSTRAINT agreements_total_cents_check CHECK (total_cents > 0 AND total_cents <= '.self::MAX.')');

        DB::statement('ALTER TABLE agreements ALTER COLUMN first_due_date SET NOT NULL');
        DB::statement('ALTER TABLE agreements ALTER COLUMN installment_count SET NOT NULL');
        DB::statement('ALTER TABLE agreements ALTER COLUMN total_cents SET NOT NULL');

        Schema::table('agreements', function (Blueprint $table) {
            $table->dropUnique(['space_id', 'idempotency_key']);
            $table->dropColumn([
                'kind',
                'is_variable',
                'amount_cents',
                'estimated_amount_cents',
                'start_date',
                'reference_day',
                'end_date',
                'initial_until',
                'idempotency_key',
            ]);
        });
    }
};
