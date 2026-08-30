<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
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
            'USR_MOBILE_NUMBER' => ['required', 'string', 'max:20', 'unique:user,USR_MOBILE_NUMBER'],
        ]);

        do {
            $id = strtoupper(Str::random(6));
        } while (User::where('USR_ID', $id)->exists());

        $user = User::create([
            'USR_ID' => $id,
            'USR_NAME' => $validated['USR_NAME'],
            'USR_EMAIL' => $validated['USR_EMAIL'],
            'USR_PASSWORD' => Hash::make($validated['USR_PASSWORD']),
            'USR_MOBILE_NUMBER' => $validated['USR_MOBILE_NUMBER'],
            'USR_ROLE' => 'GENERAL_USER',
            'USR_IS_SELLER' => 0,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);

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
            return response()->json([
                'message' => $user->USR_STATUS === 'DEACTIVATED'
                    ? 'This account has been deactivated.'
                    : 'This account is pending verification.',
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