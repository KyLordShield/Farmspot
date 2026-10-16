<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Refuse API requests from an account an admin has locked.
 *
 * Login already checks USR_STATUS and deactivation already revokes the
 * account's tokens, so in the normal case this middleware never fires: the
 * token is gone and Sanctum answers 401 first. It exists for the cases where a
 * token survives — a token minted in the same second as the deactivation, a row
 * restored from a backup, a future code path that forgets to revoke. Without
 * it, "deactivated" would only ever mean "cannot log in again", and an app that
 * was already open would keep full access, which is precisely the bug.
 *
 * The refusal is deliberately identical to AuthController::login — same codes,
 * same reason — so the app shows the same taken-down screen (with its appeal
 * form) no matter which request found the account out.
 */
class EnsureAccountIsActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user && $user->USR_STATUS !== 'ACTIVE') {
            // Kill the token that got in, so the block cannot be retried.
            $user->currentAccessToken()?->delete();

            if ($user->USR_STATUS === 'DEACTIVATED') {
                if ($user->USR_TAKEDOWN_REASON !== null) {
                    return response()->json([
                        'message' => 'This account has been taken down.',
                        'code' => 'ACCOUNT_TAKEN_DOWN',
                        'reason' => $user->USR_TAKEDOWN_REASON,
                    ], 403);
                }

                return response()->json([
                    'message' => 'This account has been deactivated.',
                    'code' => 'ACCOUNT_DEACTIVATED',
                ], 403);
            }

            return response()->json([
                'message' => 'This account is pending verification.',
                'code' => 'ACCOUNT_PENDING_VERIFICATION',
            ], 403);
        }

        return $next($request);
    }
}
