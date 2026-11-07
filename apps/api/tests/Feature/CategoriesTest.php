<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CategoriesTest extends TestCase
{
    use DatabaseTransactions;

    private User $user;

    private Space $pf;

    private Space $pj;

    protected function setUp(): void
    {
        parent::setUp();
        [$this->user, $this->pf, $this->pj] = $this->userWithSpaces();
        Sanctum::actingAs($this->user);
    }

    public function test_can_list_categories_and_filter_by_type(): void
    {
        Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Salário Teste',
            'type' => 'income',
            'icon' => 'work',
            'color' => '#0F8A5F',
            'is_default' => true,
        ]);

        Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Mercado Teste',
            'type' => 'expense',
            'icon' => 'restaurant',
            'color' => '#E57373',
            'is_default' => false,
        ]);

        // List all
        $responseAll = $this->getJson("/api/spaces/{$this->pf->id}/categories");
        $responseAll->assertOk();
        $this->assertGreaterThanOrEqual(2, count($responseAll->json('data')));

        // Filter income
        $responseIncome = $this->getJson("/api/spaces/{$this->pf->id}/categories?type=income");
        $responseIncome->assertOk();
        foreach ($responseIncome->json('data') as $cat) {
            $this->assertEquals('income', $cat['type']);
        }

        // Filter expense
        $responseExpense = $this->getJson("/api/spaces/{$this->pf->id}/categories?type=expense");
        $responseExpense->assertOk();
        foreach ($responseExpense->json('data') as $cat) {
            $this->assertEquals('expense', $cat['type']);
        }
    }

    public function test_can_create_custom_category(): void
    {
        $response = $this->postJson("/api/spaces/{$this->pf->id}/categories", [
            'name' => 'Pet Shop & Veterinário',
            'type' => 'expense',
            'icon' => 'pets',
            'color' => '#FFB74D',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.name', 'Pet Shop & Veterinário')
            ->assertJsonPath('data.type', 'expense')
            ->assertJsonPath('data.icon', 'pets')
            ->assertJsonPath('data.color', '#FFB74D')
            ->assertJsonPath('data.is_default', false);
    }

    public function test_duplicate_category_name_in_same_space_and_type_is_rejected(): void
    {
        Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Academia',
            'type' => 'expense',
            'icon' => 'fitness_center',
            'color' => '#BA68C8',
        ]);

        $response = $this->postJson("/api/spaces/{$this->pf->id}/categories", [
            'name' => 'Academia',
            'type' => 'expense',
            'icon' => 'fitness_center',
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['name']);
    }

    public function test_cannot_delete_default_category(): void
    {
        $category = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Alimentação Padrão',
            'type' => 'expense',
            'icon' => 'restaurant',
            'color' => '#FFB74D',
            'is_default' => true,
        ]);

        $response = $this->deleteJson("/api/spaces/{$this->pf->id}/categories/{$category->id}");

        $response->assertStatus(422)
            ->assertJsonPath('message', 'Categorias padrão do sistema não podem ser excluídas.');
    }

    public function test_can_delete_custom_category(): void
    {
        $category = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Hobby Especial',
            'type' => 'expense',
            'icon' => 'palette',
            'color' => '#4DD0E1',
            'is_default' => false,
        ]);

        $response = $this->deleteJson("/api/spaces/{$this->pf->id}/categories/{$category->id}");

        $response->assertOk()
            ->assertJsonPath('data.deleted', true);

        $this->assertDatabaseMissing('categories', ['id' => $category->id]);
    }

    public function test_idor_isolation_cannot_access_or_modify_other_space_categories(): void
    {
        [$otherUser, $otherPf] = $this->userWithSpaces('other@example.com');

        $otherCat = Category::create([
            'space_id' => $otherPf->id,
            'name' => 'Categoria Privada Alheia',
            'type' => 'expense',
            'icon' => 'lock',
            'color' => '#E57373',
            'is_default' => false,
        ]);

        // Tentativa de deletar categoria de outro usuário/espaço
        $response = $this->deleteJson("/api/spaces/{$otherPf->id}/categories/{$otherCat->id}");

        $response->assertNotFound();
    }
}
