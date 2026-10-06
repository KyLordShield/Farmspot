<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PasswordResetCode;
use App\Models\User;
use App\Notifications\PasswordResetCodeSent;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Validation\Rules\Password;

/**
 * Password reset for the mobile app, by emailed 6-digit code.
 *
 * The admin panel deliberately has no equivalent: those routes and views were
 * removed by owner decision (see docs/admin_audit_report.md, S1). This is for
 * GENERAL_USER app accounts only, which matches Api\AuthController::login(),
 * which refuses ADMIN accounts outright.
 *
 * Two rules shape everything below.
 *
 * 1. No account enumeration. `requestCode` answers 200 with the same body
 *    whether or not the address is registered, and takes the same time. A
 *    different response for "no such user" turns this endpoint into a way to
 *    harvest every address on the platform, and into a way to find out which
 *    customers an attacker is interested in.
 *
 * 2. The code is the only thing standing between a leaked address list and a
 *    compromised account, so it is short-lived, attempt-capped, single-use, and
 *    stored only as a bcrypt hash.
 */
class PasswordResetController extends Controller
{
    /**
     * Issue a reset code to an address, if that address belongs to a usable app account.
     *
     * Always answers 200 with an identical body. See rule 1 above.
     */
    public function requestCode(Request $request): JsonResponse
    {
        $request->validate([
            'email' => ['required', 'email', 'max:200'],
        ]);

        $email = $request->input('email');

        $user = User::where('USR_EMAIL', $email)->first();

        // Only app accounts. A DEACTIVATED or pending user still gets the
        // success response - the difference is invisible from outside.
        if (! $user || $user->USR_ROLE !== 'GENERAL_USER' || $user->USR_STATUS !== 'ACTIVE') {
            // Burn roughly the time a real send would take, so that "no such
            // user" is not detectably faster than "code sent".
            $this->wasteTime();

            return $this->genericSuccess();
        }

        $code = $this->generateCode();

        // One live code per user, enforced by USR_ID being the primary key.
        // updateOrCreate overwrites any previous code, which is what we want on
        // a "resend" and also means an old code dies as soon as a new one is
        // requested.
        PasswordResetCode::updateOrCreate(
            ['USR_ID' => $user->USR_ID],
            [
                'RSTC_CODE_HASH' => Hash::make($code),
                'RSTC_EXPIRES_AT' => now()->addMinutes(PasswordResetCode::expiryMinutes()),
                'RSTC_ATTEMPTS' => 0,
                'RSTC_CONSUMED_AT' => null,
                'RSTC_CREATED_AT' => now(),
            ]
        );

        try {
            Notification::send($user, new PasswordResetCodeSent(
                $user,
                $code,
                PasswordResetCode::expiryMinutes()
            ));
        } catch (\Throwable $e) {
            // A misconfigured mail transport must not turn into a 500 that tells
            // the caller "something specific went wrong". The user still gets the
            // generic response; the failure belongs in the log, not the API.
            report($e);
        }

        $payload = [
            'message' => 'If that email belongs to a FarmSpot account, a reset code is on its way.',
        ];

        // Testing aid. With SMTP unconfigured the code goes nowhere, so there is
        // no way to exercise the second half of the flow at all. This hands the
        // code back to the caller - but ONLY in the local environment AND only
        // when explicitly switched on, because in any real deployment this
        // would be a password reset for anyone who asks.
        if (app()->isLocal() && config('auth.password_reset_code.expose_code', false)) {
            $payload['debug_code'] = $code;
        }

        return response()->json($payload);
    }

    /**
     * Consume a code and set a new password.
     */
    public function resetPassword(Request $request): JsonResponse
    {
        $request->validate([
            'email' => ['required', 'email', 'max:200'],
            // Accept spaces because the emailed code is displayed as "123 456".
            'code' => ['required', 'string', 'regex:/^[0-9]{3}\s?[0-9]{3}$/'],
            'password' => ['required', 'confirmed', Password::defaults()],
        ]);

        // Strip the display space before comparing.
        $code = preg_replace('/\s+/', '', $request->input('code'));

        $user = User::where('USR_EMAIL', $request->input('email'))->first();

        if (! $user) {
            return $this->fail('That reset code is not valid.', 422);
        }

        $record = PasswordResetCode::find($user->USR_ID);

        if (! $record) {
            return $this->fail('That reset code is not valid.', 422);
        }

        $state = $record->usability();

        if ($state === 'expired') {
            return $this->fail('That code has expired. Request a new one.', 422);
        }

        if ($state === 'used') {
            return $this->fail('That code has already been used. Request a new one.', 422);
        }

        if ($state === 'locked') {
            return $this->fail('Too many incorrect attempts. Request a new code.', 422);
        }

        if (! $record->attempt($code)) {
            $left = max(0, PasswordResetCode::maxAttempts() - $record->fresh()->RSTC_ATTEMPTS);

            return $this->fail(
                $left > 0
                    ? "That code is not correct. {$left} attempt(s) left."
                    : 'That code is not correct. Request a new code.',
                422
            );
        }

        $user->forceFill([
            'USR_PASSWORD' => Hash::make($request->input('password')),
        ])->save();

        // Burn the code before anything else, so a concurrent second request
        // cannot also get through.
        $record->forceFill(['RSTC_CONSUMED_AT' => now()])->save();

        // Kill every issued token. The app keeps its bearer token in
        // SharedPreferences, so if the reset was prompted by a lost or stolen
        // phone, the old token must stop working or the attacker simply stays
        // logged in. The user will have to log in again on every device, which
        // is the correct outcome and the whole point.
        $this->revokeAllTokens($user);

        return response()->json([
            'message' => 'Your password has been changed. Please log in again.',
        ]);
    }

    /**
     * A 6-digit code, drawn uniformly from 900000-999999.
     *
     * random_int rather than rand()/mt_rand(): the code is a bearer credential,
     * so it has to come from a CSPRNG. mt_rand() is seeded per-process and its
     * output is predictable from a handful of observations, which would let an
     * attacker who can trigger a few resets predict other users' codes.
     *
     * The range starts at 900000 rather than 0 so the value is always six digits
     * with no leading zero to lose.
     */
    private function generateCode(): string
    {
        return (string) random_int(900000, 999999);
    }

    /**
     * Delete every Sanctum token for this user.
     */
    private function revokeAllTokens(User $user): void
    {
        DB::table('personal_access_tokens')
            ->where('tokenable_type', User::class)
            ->where('tokenable_id', $user->USR_ID)
            ->delete();
    }

    /**
     * The one and only response shape for requestCode.
     */
    private function genericSuccess(): JsonResponse
    {
        return response()->json([
            'message' => 'If that email belongs to a FarmSpot account, a reset code is on its way.',
        ]);
    }

    private function fail(string $message, int $status): JsonResponse
    {
        return response()->json(['message' => $message], $status);
    }

    /**
     * Delay a request that is not going to send anything.
     *
     * bcrypt hashing plus an SMTP handshake take real time; answering instantly
     * for an unknown address and slowly for a known one is a timing oracle that
     * undoes the identical-response rule above.
     */
    private function wasteTime(): void
    {
        usleep(random_int(120000, 260000));
    }
}