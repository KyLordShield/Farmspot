<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureUserIsAdmin
{
    /**
     * Allow only users with the ADMIN role through to admin-only pages and
     * endpoints.
     *
     * The same middleware guards the api/admin/* routes and the admin panel.
     * The two used to differ: the API returned a JSON 403, and the web panel had
     * no check at all, so any signed-in web account could open the report queue
     * and read reported message text and the names of the people accused. It
     * answers a browser differently from an API client on purpose, and both
     * ways of saying no are a 403.
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user || $user->USR_ROLE !== 'ADMIN') {
            if ($request->expectsJson()) {
                return response()->json([
                    'message' => 'Unauthorized. Admin access required.',
                ], 403);
            }

            // A browser that lands here is not an API client, so a JSON blob
            // would be a dead end. 403 rather than a redirect: being refused is
            // correct, and bouncing to the dashboard would hide that.
            abort(403, 'Admin access required.');
        }

        return $next($request);
    }
}
