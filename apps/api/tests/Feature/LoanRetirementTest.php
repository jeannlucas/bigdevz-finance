<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use RuntimeException;
use Tests\TestCase;

class LoanRetirementTest extends TestCase
{
    use DatabaseTransactions;

    public function test_ac_emp_009_disables_loan_routes_and_removes_empty_schema(): void
    {
        [$user, $space] = $this->userWithSpaces();
        $this->actingAs($user, 'sanctum');
        $url = "/api/spaces/{$space->id}/loans";
        $this->getJson($url)->assertNotFound();
        $this->postJson($url, [])->assertNotFound();
        $this->getJson("$url/1")->assertNotFound();
        $this->assertFalse(Schema::hasTable('loans'));
        $this->assertFalse(Schema::hasColumn('account_movements', 'loan_disbursement_id'));
        $this->assertFalse(Schema::hasColumn('idempotency_keys', 'loan_id'));
    }

    public function test_ac_emp_009_refuses_to_remove_a_populated_legacy_table(): void
    {
        [$user, $space] = $this->userWithSpaces();
        $migration = require database_path('migrations/2026_11_24_093000_retire_empty_loans_module.php');
        $migration->down();
        $date = '2026-11-24';
        $agreement = DB::table('agreements')->insertGetId([
            'space_id' => $space->id, 'description' => 'Acordo de teste',
            'total_cents' => 10000, 'installment_count' => 1, 'first_due_date' => $date,
        ]);
        $loan = DB::table('loans')->insertGetId([
            'space_id' => $space->id, 'user_id' => $user->id, 'kind' => 'granted',
            'title' => 'Registro de teste', 'counterparty' => 'Contraparte de teste',
            'principal_cents' => 10000, 'total_cents' => 10000, 'installment_count' => 1,
            'first_due_date' => $date, 'agreement_id' => $agreement,
        ]);

        try {
            $migration->up();
            $this->fail('A estrutura ocupada deveria ser preservada.');
        } catch (RuntimeException $error) {
            $this->assertStringContainsString('existem registros vinculados', $error->getMessage());
        }
        $this->assertDatabaseHas('loans', ['id' => $loan, 'agreement_id' => $agreement]);
        $this->assertDatabaseHas('agreements', ['id' => $agreement, 'total_cents' => 10000]);
    }
}
