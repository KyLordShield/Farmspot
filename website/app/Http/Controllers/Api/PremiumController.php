<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PremiumController extends Controller
{
    public function show(Request $request)
    {
        return response()->json([
            'simulation_enabled' => (bool) config('premium.simulation_enabled'),
            'user' => $request->user(),
        ]);
    }

    public function simulatePurchase(Request $request)
    {
        abort_unless(config('premium.simulation_enabled'), 403, 'Simulated purchases are not available on this server.');
        abort_unless($request->user()->USR_ROLE === 'GENERAL_USER', 403, 'Premium is available to app users only.');

        // Lock the account so retries and concurrent taps grant only one period.
        // Never accept an account id, price, or entitlement dates from the app.
        $user = DB::transaction(function () use ($request) {
            $user = User::whereKey($request->user()->getKey())->lockForUpdate()->firstOrFail();
            if (! $user->USR_IS_PREMIUM) {
                $user->USR_PREMIUM_STARTED_AT = now();
                $user->USR_PREMIUM_EXPIRES_AT = now()->addMonthNoOverflow();
                $user->save();
            }

            return $user;
        });

        return response()->json([
            'message' => 'Premium is active. This was a simulated purchase; no money was charged.',
            'simulated' => true,
            'user' => $user,
        ]);
    }
}
