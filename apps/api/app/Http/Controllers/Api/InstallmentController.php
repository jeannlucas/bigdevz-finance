<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\InstallmentResource;
use Illuminate\Http\Request;

class InstallmentController extends Controller
{
    public function show(Request $request, string $space, string $installment): InstallmentResource
    {
        return new InstallmentResource(
            $this->space($request, $space)->installments()->with(['agreement', 'receipts.reversal', 'receipts.correctionOf'])->findOrFail($installment),
        );
    }
}
