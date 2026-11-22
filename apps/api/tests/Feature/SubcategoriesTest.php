<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Payable;
use App\Models\Space;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SubcategoriesTest extends TestCase
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

    public function test_can_create_subcategory_under_parent_with_same_space_and_type(): void
    {
        $parent = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Moradia Teste',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        $response = $this->postJson("/api/spaces/{$this->pf->id}/categories", [
            'name' => 'Energia Elétrica',
            'type' => 'expense',
            'parent_id' => $parent->id,
            'icon' => 'bolt',
            'color' => '#FFA000',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.name', 'ENERGIA ELÉTRICA')
            ->assertJsonPath('data.parent_id', $parent->id)
            ->assertJsonPath('data.parent_name', 'MORADIA TESTE');

        $this->assertDatabaseHas('categories', [
            'name' => 'ENERGIA ELÉTRICA',
            'parent_id' => $parent->id,
            'space_id' => $this->pf->id,
        ]);
    }

    public function test_cannot_create_subcategory_with_incompatible_type(): void
    {
        $parent = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Moradia Despesa',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        $response = $this->postJson("/api/spaces/{$this->pf->id}/categories", [
            'name' => 'Renda Aluguel',
            'type' => 'income',
            'parent_id' => $parent->id,
            'icon' => 'bolt',
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['parent_id']);
    }

    public function test_cannot_create_subcategory_with_parent_from_another_space(): void
    {
        $parentInPj = Category::create([
            'space_id' => $this->pj->id,
            'name' => 'Despesas Operacionais PJ',
            'type' => 'expense',
            'icon' => 'business',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        $response = $this->postJson("/api/spaces/{$this->pf->id}/categories", [
            'name' => 'Tentativa Invasão Tenant',
            'type' => 'expense',
            'parent_id' => $parentInPj->id,
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['parent_id']);
    }

    public function test_cannot_create_third_level_subcategory(): void
    {
        $parent = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Nível 1 Principal',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        $child = Category::create([
            'space_id' => $this->pf->id,
            'parent_id' => $parent->id,
            'name' => 'Nível 2 Filha',
            'type' => 'expense',
            'icon' => 'bolt',
            'color' => '#FFA000',
            'is_default' => false,
        ]);

        $response = $this->postJson("/api/spaces/{$this->pf->id}/categories", [
            'name' => 'Nível 3 Bloqueado',
            'type' => 'expense',
            'parent_id' => $child->id,
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['parent_id']);
    }

    public function test_cannot_set_category_as_its_own_parent(): void
    {
        $category = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Auto Referência',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        $response = $this->putJson("/api/spaces/{$this->pf->id}/categories/{$category->id}", [
            'parent_id' => $category->id,
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['parent_id']);
    }

    public function test_parent_with_children_cannot_become_a_child(): void
    {
        $grandparent = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Nova Principal',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        $parent = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Categoria Pai',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        Category::create([
            'space_id' => $this->pf->id,
            'parent_id' => $parent->id,
            'name' => 'Categoria Filha',
            'type' => 'expense',
            'icon' => 'bolt',
            'color' => '#FFA000',
            'is_default' => false,
        ]);

        $response = $this->putJson("/api/spaces/{$this->pf->id}/categories/{$parent->id}", [
            'parent_id' => $grandparent->id,
        ]);

        $response->assertStatus(422)
            ->assertJsonValidationErrors(['parent_id']);
    }

    public function test_cannot_delete_parent_category_with_children(): void
    {
        $parent = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Moradia Pai Delete',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        Category::create([
            'space_id' => $this->pf->id,
            'parent_id' => $parent->id,
            'name' => 'Energia Filha Delete',
            'type' => 'expense',
            'icon' => 'bolt',
            'color' => '#FFA000',
            'is_default' => false,
        ]);

        $response = $this->deleteJson("/api/spaces/{$this->pf->id}/categories/{$parent->id}");

        $response->assertStatus(422)
            ->assertJsonPath('message', 'Não é possível excluir uma categoria que possui subcategorias.');

        $this->assertDatabaseHas('categories', ['id' => $parent->id]);
    }

    public function test_summary_groups_parent_and_children_and_avoids_double_counting(): void
    {
        $parent = Category::create([
            'space_id' => $this->pf->id,
            'name' => 'Moradia Grupo',
            'type' => 'expense',
            'icon' => 'home',
            'color' => '#1E88E5',
            'is_default' => false,
        ]);

        $child = Category::create([
            'space_id' => $this->pf->id,
            'parent_id' => $parent->id,
            'name' => 'Energia Grupo',
            'type' => 'expense',
            'icon' => 'bolt',
            'color' => '#FFA000',
            'is_default' => false,
        ]);

        // R$ 30,00 classificado diretamente na principal (Moradia)
        Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Condomínio Moradia',
            'amount_cents' => 3000,
            'paid_cents' => 0,
            'due_date' => now()->toDateString(),
            'category_id' => $parent->id,
        ]);

        // R$ 50,00 classificado na filha (Energia)
        Payable::create([
            'space_id' => $this->pf->id,
            'kind' => Payable::SINGLE,
            'description' => 'Conta de Luz',
            'amount_cents' => 5000,
            'paid_cents' => 0,
            'due_date' => now()->toDateString(),
            'category_id' => $child->id,
        ]);

        $response = $this->getJson("/api/spaces/{$this->pf->id}/summary");
        $response->assertOk();

        $expenses = $response->json('data.categories_summary.expenses');

        // Encontra o grupo Moradia
        $group = collect($expenses)->firstWhere('id', $parent->id);
        $this->assertNotNull($group, 'Grupo Moradia deve estar presente na agregação');

        // O grupo deve somar R$ 80,00
        $this->assertEquals(8000, $group['total_cents']);
        $this->assertEquals('80.00', $group['total']);

        // Deve conter os itens detalhados da composição
        $this->assertArrayHasKey('composition', $group);
        $direct = collect($group['composition'])->firstWhere('id', $parent->id);
        $this->assertNotNull($direct, 'Deve conter valor classificado diretamente na principal');
        $this->assertEquals(3000, $direct['total_cents']);

        $childItem = collect($group['composition'])->firstWhere('id', $child->id);
        $this->assertNotNull($childItem, 'Deve conter a subcategoria Energia');
        $this->assertEquals(5000, $childItem['total_cents']);
    }
}
