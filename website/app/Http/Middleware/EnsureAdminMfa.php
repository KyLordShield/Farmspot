<?php

namespace App\Http\Middleware;

use App\Services\AdminMfa;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

class EnsureAdminMfa
{
    public function handle(Request $request, Closure $next, string $mode = 'web'): Response
    {
        $user = $request->user();
        $session = $request->hasSession() ? $request->session() : null;
        $now = now()->timestamp;

        if ($user?->USR_STATUS === 'ACTIVE' && $session) {
            $fingerprint = app(AdminMfa::class)->fingerprint($user);
            if ($session->get('admin_mfa.verified') === $fingerprint
                && $now - $session->get('admin_mfa.started', 0) < 8 * 3600
                && $now - $session->get('admin_mfa.last_seen', 0) < 30 * 60) {
                $session->put('admin_mfa.last_seen', $now);

                $response = $next($request);
                $response->headers->set('Cache-Control', 'no-store');

                return $response;
            }
        }

        if ($mode === 'api') {
            abort(403, 'A verified administrator session is required.');
        }

        if ($session && app(AdminMfa::class)->isPending($request)) {
            return $request->expectsJson()
                ? response()->json(['message' => 'Administrator verification is required.'], 403)
                : redirect()->route('admin.mfa');
        }

        Auth::guard('web')->logout();
        $session->invalidate();
        $session->regenerateToken();

        return $request->expectsJson()
            ? response()->json(['message' => 'Please sign in again.'], 401)
            : redirect()->route('login')->with('status', 'Please sign in again.');
    }
}
