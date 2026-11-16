<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    private const MAX_CENTS = 99999999999999;

    public function up(): void
    {
        DB::statement('ALTER TABLE accounts DROP CONSTRAINT accounts_opening_balance_cents_check');
        DB::statement('ALTER TABLE accounts ADD CONSTRAINT accounts_opening_balance_cents_check CHECK (opening_balance_cents >= -'.self::MAX_CENTS.' AND opening_balance_cents <= '.self::MAX_CENTS.')');

        DB::statement('ALTER TABLE account_opening_adjustments DROP CONSTRAINT account_opening_adjustments_previous_opening_balance_cents_check');
        DB::statement('ALTER TABLE account_opening_adjustments ADD CONSTRAINT account_opening_adjustments_previous_opening_balance_cents_check CHECK (previous_opening_balance_cents >= -'.self::MAX_CENTS.' AND previous_opening_balance_cents <= '.self::MAX_CENTS.')');

        DB::statement('ALTER TABLE account_opening_adjustments DROP CONSTRAINT account_opening_adjustments_new_opening_balance_cents_check');
        DB::statement('ALTER TABLE account_opening_adjustments ADD CONSTRAINT account_opening_adjustments_new_opening_balance_cents_check CHECK (new_opening_balance_cents >= -'.self::MAX_CENTS.' AND new_opening_balance_cents <= '.self::MAX_CENTS.')');
    }

    public function down(): void
    {
        DB::statement('ALTER TABLE accounts DROP CONSTRAINT accounts_opening_balance_cents_check');
        DB::statement('ALTER TABLE accounts ADD CONSTRAINT accounts_opening_balance_cents_check CHECK (opening_balance_cents >= 0 AND opening_balance_cents <= '.self::MAX_CENTS.')');

        DB::statement('ALTER TABLE account_opening_adjustments DROP CONSTRAINT account_opening_adjustments_previous_opening_balance_cents_check');
        DB::statement('ALTER TABLE account_opening_adjustments ADD CONSTRAINT account_opening_adjustments_previous_opening_balance_cents_check CHECK (previous_opening_balance_cents >= 0 AND previous_opening_balance_cents <= '.self::MAX_CENTS.')');

        DB::statement('ALTER TABLE account_opening_adjustments DROP CONSTRAINT account_opening_adjustments_new_opening_balance_cents_check');
        DB::statement('ALTER TABLE account_opening_adjustments ADD CONSTRAINT account_opening_adjustments_new_opening_balance_cents_check CHECK (new_opening_balance_cents >= 0 AND new_opening_balance_cents <= '.self::MAX_CENTS.')');
    }
};
