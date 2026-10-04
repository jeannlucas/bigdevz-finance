<?php

use App\Actions\Receivables\IdempotencyConflict;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\HttpKernel\Exception\TooManyRequestsHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        //
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
        // Mensagens curtas, em português e sem detalhes internos.
        $exceptions->render(fn (IdempotencyConflict $error) => response()->json(['message' => $error->getMessage()], 409));
        $exceptions->render(fn (NotFoundHttpException $error, Request $request) => $request->is('api/*')
            ? response()->json(['message' => 'Registro não encontrado.'], 404) : null);
        $exceptions->render(fn (AuthenticationException $error, Request $request) => $request->is('api/*')
            ? response()->json(['message' => 'Sessão expirada ou inválida. Entre novamente.'], 401) : null);
        $exceptions->render(fn (TooManyRequestsHttpException $error, Request $request) => $request->is('api/*')
            ? response()->json(['message' => 'Muitas tentativas. Aguarde um minuto.'], 429, $error->getHeaders()) : null);
    })->create();
