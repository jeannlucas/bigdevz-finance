<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\CategoryResource;
use App\Models\Category;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

class CategoryController extends Controller
{
    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        $spaceModel = $this->space($request, $space);
        $query = $spaceModel->categories()->orderBy('name');

        if ($request->has('type') && in_array($request->query('type'), [Category::TYPE_INCOME, Category::TYPE_EXPENSE], true)) {
            $query->where('type', $request->query('type'));
        }

        return CategoryResource::collection($query->get());
    }

    public function store(Request $request, string $space): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $spaceModel->ensureCan($request->user(), 'manage_categories');

        if ($request->has('name')) {
            $request->merge(['name' => Category::financialUpper($request->input('name'))]);
        }

        $data = $request->validate([
            'name' => [
                'required',
                'string',
                'max:60',
                Rule::unique('categories')->where(fn ($query) => $query->where('space_id', $spaceModel->id)->where('type', $request->input('type'))),
            ],
            'type' => ['required', 'string', Rule::in([Category::TYPE_INCOME, Category::TYPE_EXPENSE])],
            'icon' => ['nullable', 'string', 'max:50'],
            'color' => ['nullable', 'string', 'max:10'],
        ]);

        $category = Category::create([
            'space_id' => $spaceModel->id,
            'name' => $data['name'],
            'type' => $data['type'],
            'icon' => $data['icon'] ?? ($data['type'] === Category::TYPE_INCOME ? 'trending_up' : 'shopping_cart'),
            'color' => $data['color'] ?? ($data['type'] === Category::TYPE_INCOME ? '#0F8A5F' : '#E57373'),
            'is_default' => false,
        ]);

        return (new CategoryResource($category))->response()->setStatusCode(201);
    }

    public function update(Request $request, string $space, string $category): CategoryResource
    {
        $spaceModel = $this->space($request, $space);
        $spaceModel->ensureCan($request->user(), 'manage_categories');

        /** @var Category $categoryModel */
        $categoryModel = $spaceModel->categories()->findOrFail($category);

        if ($request->has('name')) {
            $request->merge(['name' => Category::financialUpper($request->input('name'))]);
        }

        $data = $request->validate([
            'name' => [
                'sometimes',
                'required',
                'string',
                'max:60',
                Rule::unique('categories')
                    ->where(fn ($query) => $query->where('space_id', $spaceModel->id)->where('type', $categoryModel->type))
                    ->ignore($categoryModel->id),
            ],
            'icon' => ['nullable', 'string', 'max:50'],
            'color' => ['nullable', 'string', 'max:10'],
        ]);

        $categoryModel->update($data);

        return new CategoryResource($categoryModel->fresh());
    }

    public function destroy(Request $request, string $space, string $category): JsonResponse
    {
        $spaceModel = $this->space($request, $space);
        $spaceModel->ensureCan($request->user(), 'manage_categories');

        /** @var Category $categoryModel */
        $categoryModel = $spaceModel->categories()->findOrFail($category);

        if ($categoryModel->is_default) {
            return response()->json([
                'message' => 'Categorias padrão do sistema não podem ser excluídas.',
            ], 422);
        }

        $categoryModel->delete();

        return response()->json([
            'data' => ['deleted' => true],
        ]);
    }
}
