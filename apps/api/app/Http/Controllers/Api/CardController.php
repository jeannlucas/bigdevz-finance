<?php

namespace App\Http\Controllers\Api;

use App\Actions\Payables\ChangeObligations;
use App\Actions\Payables\GenerateObligations;
use App\Domain\Receivables\MonthlyDate;
use App\Http\Controllers\Controller;
use App\Http\Resources\CardResource;
use App\Models\Card;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;

/** Cartões: nome e dia de vencimento; faturas pelo total. Sem dados do cartão. */
class CardController extends Controller
{
    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        return CardResource::collection($this->space($request, $space)->cards()->orderBy('name')->get());
    }

    public function store(Request $request, string $space, GenerateObligations $generate): JsonResponse
    {
        $space = $this->space($request, $space);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:80'],
            'due_day' => ['required', 'integer', 'min:1', 'max:31'],
        ]);
        $card = DB::transaction(function () use ($space, $data, $generate) {
            $card = Card::create([
                'space_id' => $space->id, 'name' => $data['name'], 'due_day' => (int) $data['due_day'],
                'first_cycle' => MonthlyDate::cycle(GenerateObligations::today()),
            ]);
            $generate->forCard(Card::query()->lockForUpdate()->findOrFail($card->id));

            return $card;
        });

        return (new CardResource($card->fresh()))->response()->setStatusCode(201);
    }

    public function archive(Request $request, string $space, string $card, ChangeObligations $change): CardResource
    {
        return $this->setArchived($request, $space, $card, $change, true);
    }

    public function unarchive(Request $request, string $space, string $card, ChangeObligations $change): CardResource
    {
        return $this->setArchived($request, $space, $card, $change, false);
    }

    private function setArchived(Request $request, string $space, string $card, ChangeObligations $change, bool $archived): CardResource
    {
        $space = $this->space($request, $space);
        $model = $space->cards()->findOrFail($card);

        return new CardResource($change->archiveCard($request->user(), $space, $model->id, $archived));
    }
}
