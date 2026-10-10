<?php

namespace App\Http\Controllers\Api;

use App\Actions\Payables\ChangeObligations;
use App\Actions\Payables\GenerateObligations;
use App\Http\Controllers\Controller;
use App\Http\Resources\RecurrenceResource;
use App\Rules\MoneyAmount;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/** Recorrências mensais. Edição vale para ocorrências futuras sem pagamento. */
class RecurrenceController extends Controller
{
    public function index(Request $request, string $space): AnonymousResourceCollection
    {
        return RecurrenceResource::collection($this->space($request, $space)->recurrences()->orderBy('description')->get());
    }

    public function update(Request $request, string $space, string $recurrence, ChangeObligations $change): RecurrenceResource
    {
        $space = $this->space($request, $space);
        $model = $space->recurrences()->findOrFail($recurrence);
        $data = $request->validate([
            'description' => ['sometimes', 'required', 'string', 'max:120'],
            'payee' => ['sometimes', 'nullable', 'string', 'max:120'],
            'amount' => ['sometimes', 'required', new MoneyAmount],
        ]);

        return new RecurrenceResource($change->editRecurrence($request->user(), $space, $model->id, $data));
    }

    public function end(Request $request, string $space, string $recurrence, ChangeObligations $change): RecurrenceResource
    {
        $space = $this->space($request, $space);
        $model = $space->recurrences()->findOrFail($recurrence);
        $data = $request->validate([
            'end_date' => ['nullable', 'date_format:Y-m-d'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        return new RecurrenceResource($change->endRecurrence(
            $request->user(), $space, $model->id, $data['end_date'] ?? GenerateObligations::today(), $data['reason'] ?? null,
        ));
    }
}
