<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\LegalPolicies;
use App\Support\MobileNumber;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class AuthController extends Controller
{
    /**
     * Register a new GENERAL_USER (buyer/farmer) account via the mobile app.
     */
    public function register(Request $request)
    {
        $validated = $request->validate([
            'USR_NAME' => ['required', 'string', 'max:150'],
            'USR_EMAIL' => ['required', 'email', 'max:200', 'unique:user,USR_EMAIL'],
            'USR_PASSWORD' => ['required', 'confirmed', Password::defaults()],
            'USR_MOBILE_NUMBER' => ['bail', 'required', 'string', MobileNumber::PATTERN, 'unique:user,USR_MOBILE_NUMBER'],
            // Optional — the buyer can skip it, and existing test flows don't send it.
            'address' => ['nullable', 'string', 'max:255'],
        ], MobileNumber::messages('USR_MOBILE_NUMBER'));

        $legal = app(LegalPolicies::class);
        $acceptLegal = $legal->validateRegistration($request);

        do {
            $id = strtoupper(Str::random(6));
        } while (User::where('USR_ID', $id)->exists());

        $user = DB::transaction(function () use ($id, $validated, $legal, $acceptLegal) {
            $user = User::create([
                'USR_ID' => $id,
                'USR_NAME' => $validated['USR_NAME'],
                'USR_EMAIL' => $validated['USR_EMAIL'],
                'USR_PASSWORD' => Hash::make($validated['USR_PASSWORD']),
                'USR_MOBILE_NUMBER' => $validated['USR_MOBILE_NUMBER'],
                'USR_ADDRESS' => $validated['address'] ?? null,
                'USR_ROLE' => 'GENERAL_USER',
                'USR_IS_SELLER' => 0,
                'USR_STATUS' => 'ACTIVE',
                'USR_CREATED_AT' => now(),
            ]);

            if ($acceptLegal) {
                $legal->record($user->USR_ID, ['terms', 'privacy']);
            }

            return $user;
        });

        $token = $user->createToken('flutter-app')->plainTextToken;

        return response()->json([
            'message' => 'Registration successful.',
            'token' => $token,
            'user' => $user,
        ], 201);
    }

    /**
     * Log in an existing GENERAL_USER via the mobile app.
     * ADMIN accounts are blocked from the mobile API (opposite of the website's rule).
     */
    public function login(Request $request)
    {
        $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('USR_EMAIL', $request->email)->first();

        if (! $user || ! Hash::check($request->password, $user->USR_PASSWORD)) {
            return response()->json([
                'message' => 'Invalid credentials.',
            ], 401);
        }

        if ($user->USR_ROLE !== 'GENERAL_USER') {
            return response()->json([
                'message' => 'This login is for buyers and farmers only.',
            ], 403);
        }

        if ($user->USR_STATUS !== 'ACTIVE') {
            // A deactivation an admin recorded a reason for is a takedown the
            // owner is entitled to contest, so the app needs more than "no":
            // the code tells it which screen to show and the reason is the text
            // on it. A deactivation with no reason is not appealable — there is
            // no decision to point at — so it keeps the plain message and the
            // app offers only "contact the Association". PENDING_VERIFICATION
            // stays as it was; it is a wait, not a takedown.
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

        $token = $user->createToken('flutter-app')->plainTextToken;

        return response()->json([
            'message' => 'Login successful.',
            'token' => $token,
            'user' => $user,
        ]);
    }

    /**
     * Log out — revokes only the token used for this request,
     * not every device the user is logged in on.
     */
    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Logged out successfully.',
        ]);
    }
}
