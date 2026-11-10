<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Context;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class AssignRequestId
{
    /**
     * Injeta um identificador rastreável único em cada requisição e cabeçalho de resposta.
     */
    public function handle(Request $request, Closure $next): Response
    {
        $requestId = $request->header('X-Request-ID') ?? (string) Str::uuid();

        $request->headers->set('X-Request-ID', $requestId);
        Context::add('request_id', $requestId);

        /** @var Response $response */
        $response = $next($request);

        $response->headers->set('X-Request-ID', $requestId);

        return $response;
    }
}
