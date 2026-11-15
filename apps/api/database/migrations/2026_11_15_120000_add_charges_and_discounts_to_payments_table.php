<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const MAX_CENTS = 99999999999999;

    public function up(): void
    {
        Schema::table('payments', function (Blueprint $table) {
            $table->bigInteger('principal_cents')->nullable()->after('amount_cents');
            $table->bigInteger('interest_cents')->default(0)->after('principal_cents');
            $table->bigInteger('fine_cents')->default(0)->after('interest_cents');
            $table->bigInteger('discount_cents')->default(0)->after('fine_cents');
            $table->bigInteger('total_cents')->nullable()->after('discount_cents');
        });

        DB::statement('UPDATE payments SET principal_cents = amount_cents, total_cents = amount_cents WHERE principal_cents IS NULL');

        Schema::table('payments', function (Blueprint $table) {
            $table->bigInteger('principal_cents')->nullable(false)->change();
            $table->bigInteger('total_cents')->nullable(false)->change();
        });

        DB::statement('ALTER TABLE payments ADD CONSTRAINT payments_principal_cents_check CHECK (principal_cents > 0 AND principal_cents <= '.self::MAX_CENTS.')');
        DB::statement('ALTER TABLE payments ADD CONSTRAINT payments_interest_cents_check CHECK (interest_cents >= 0 AND interest_cents <= '.self::MAX_CENTS.')');
        DB::statement('ALTER TABLE payments ADD CONSTRAINT payments_fine_cents_check CHECK (fine_cents >= 0 AND fine_cents <= '.self::MAX_CENTS.')');
        DB::statement('ALTER TABLE payments ADD CONSTRAINT payments_discount_cents_check CHECK (discount_cents >= 0 AND discount_cents <= '.self::MAX_CENTS.')');
        DB::statement('ALTER TABLE payments ADD CONSTRAINT payments_total_cents_check CHECK (total_cents > 0 AND total_cents <= '.self::MAX_CENTS.')');
        DB::statement('ALTER TABLE payments ADD CONSTRAINT payments_composition_check CHECK (total_cents = principal_cents + interest_cents + fine_cents - discount_cents)');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_composition_check');
        DB::statement('ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_total_cents_check');
        DB::statement('ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_discount_cents_check');
        DB::statement('ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_fine_cents_check');
        DB::statement('ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_interest_cents_check');
        DB::statement('ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_principal_cents_check');

        Schema::table('payments', function (Blueprint $table) {
            $table->dropColumn(['principal_cents', 'interest_cents', 'fine_cents', 'discount_cents', 'total_cents']);
        });
    }
};
