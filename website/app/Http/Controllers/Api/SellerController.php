<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Buyer;
use App\Models\Farmer;
use App\Models\Whitelist;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class SellerController extends Controller
{
    /**
     * Activates seller mode for the authenticated user, gated by the
     * mobile-number whitelist. Lazily creates the Buyer and Farmer rows
     * if they don't already exist (registration only creates a User row).
     */
    public function activate(Request $request)
    {
        $user = $request->user();

        $isWhitelisted = Whitelist::where('WLST_MOBILE_NUMBER', $user->USR_MOBILE_NUMBER)
            ->where('WLST_IS_ACTIVE', 1)
            ->exists();

        if (! $isWhitelisted) {
            return response()->json([
                'message' => 'Your mobile number is not on the approved seller list. Please contact the Association Secretary.',
            ], 403);
        }

        $buyer = Buyer::where('USR_ID', $user->USR_ID)->first();

        if (! $buyer) {
            do {
                $buyId = strtoupper(Str::random(6));
            } while (Buyer::where('BUY_ID', $buyId)->exists());

            $buyer = Buyer::create([
                'BUY_ID' => $buyId,
                'USR_ID' => $user->USR_ID,
            ]);
        }

        $farmer = Farmer::where('BUY_ID', $buyer->BUY_ID)->first();

        if (! $farmer) {
            do {
                $fmrId = strtoupper(Str::random(6));
            } while (Farmer::where('FMR_ID', $fmrId)->exists());

            $farmer = Farmer::create([
                'FMR_ID' => $fmrId,
                'BUY_ID' => $buyer->BUY_ID,
                'FMR_SELLER_MODE_ACTIVE' => 1,
                'FMR_VERIFIED_AT' => now(),
            ]);
        } else {
            $farmer->FMR_SELLER_MODE_ACTIVE = 1;
            $farmer->FMR_VERIFIED_AT = $farmer->FMR_VERIFIED_AT ?? now();
            $farmer->save();
        }

        $user->USR_IS_SELLER = 1;
        $user->save();

        return response()->json([
            'message' => 'Seller mode activated.',
            'farmer_id' => $farmer->FMR_ID,
        ]);
    }

    /**
     * Deactivates seller mode for the authenticated user.
     * Only flips the flags — does NOT delete the Farmer, Farm, or Listing
     * rows, so reactivation preserves all existing data.
     */
    public function deactivate(Request $request)
    {
        $user = $request->user();

        $buyer = Buyer::where('USR_ID', $user->USR_ID)->first();

        if (! $buyer) {
            return response()->json([
                'message' => 'No seller profile found.',
            ], 404);
        }

        $farmer = Farmer::where('BUY_ID', $buyer->BUY_ID)->first();

        if (! $farmer || (int) $farmer->FMR_SELLER_MODE_ACTIVE !== 1) {
            return response()->json([
                'message' => 'Seller mode is not currently active.',
            ], 409);
        }

        $farmer->FMR_SELLER_MODE_ACTIVE = 0;
        $farmer->save();

        $user->USR_IS_SELLER = 0;
        $user->save();

        return response()->json([
            'message' => 'Seller mode deactivated.',
        ]);
    }
}