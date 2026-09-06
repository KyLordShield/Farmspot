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
     * creates a User row), then branches on whether the user is returning or
     * new:
     *
     * Case A — the user already has an APPROVED farm. They previously completed
     * the wizard and were approved; deactivation (SellerController@deactivate)
     * only cleared FMR_SELLER_MODE_ACTIVE / USR_IS_SELLER and never touched
     * FRM_STATUS, so reactivation simply flips those two flags back on — no
     * wizard / approval round-trip. Responds with 'reactivated' => true so the
     * app can route straight to the seller shell.
     *
     * Case B — the user has no APPROVED farm yet (first-timer, or their only
     * farm is PENDING_REVIEW/REJECTED). This is NOT the approval gate anymore
     * — whitelist approval happens later, at farm-submission time
     * (POST /api/farms). So everyone gets past here into the wizard, and
     * FMR_SELLER_MODE_ACTIVE / USR_IS_SELLER are NOT flipped. Those flags are
     * set only inside FarmController@store when a farm is actually approved
     * (whitelisted instant-approve path), so a user who calls activate() but
     * never gets an approved farm won't incorrectly show as an active seller.
     * Responds with 'reactivated' => false.
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

        // Case A: returning seller — at least one farm is APPROVED, so the
        // existing approval still stands. Reactivate by re-enabling the flags
        // deactivate() cleared; the farm itself stays untouched.
        $hasApprovedFarm = $farmer->farms()
            ->where('FRM_STATUS', 'APPROVED')
            ->exists();

        if ($hasApprovedFarm) {
            $farmer->FMR_SELLER_MODE_ACTIVE = 1;
            $farmer->save();

            $user->USR_IS_SELLER = 1;
            $user->save();

            return response()->json([
                'message' => 'Seller mode reactivated.',
                'farmer_id' => $farmer->FMR_ID,
                'reactivated' => true,
            ]);
        }

        // Case B: first-timer or no approved farm yet — Stage 1.5 behavior
        // unchanged (flags stay 0; the wizard + farm approval flips them).
        return response()->json([
            'message' => 'Seller mode activated.',
            'farmer_id' => $farmer->FMR_ID,
            'reactivated' => false,
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