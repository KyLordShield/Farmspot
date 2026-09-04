<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Buyer;
use App\Models\Farmer;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class SellerController extends Controller
{
    /**
     * Starts the seller setup for the authenticated user by lazily creating
     * the Buyer and Farmer rows if they don't already exist (registration only
     * creates a User row).
     *
     * This is NOT the approval gate anymore — whitelist approval now happens
     * later, at farm-submission time (POST /api/farms). So everyone gets past
     * here into the wizard, and FMR_SELLER_MODE_ACTIVE / USR_IS_SELLER are NOT
     * flipped here. Those flags are set only inside FarmController@store when a
     * farm is actually approved (whitelisted instant-approve path), so a user
     * who calls activate() but never gets an approved farm won't incorrectly
     * show as an active seller.
     */
    public function activate(Request $request)
    {
        $user = $request->user();

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
            ]);
        }

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