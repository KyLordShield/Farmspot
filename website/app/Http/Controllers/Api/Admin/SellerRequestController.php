<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Services\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class SellerRequestController extends Controller
{
    /**
     * List all farms awaiting review (FRM_STATUS = 'PENDING_REVIEW'),
     * oldest first, eager-loading the applicant's user details and the
     * farm's photos/verification document path.
     */
    public function index(Request $request)
    {
        $farms = Farm::with(['farmer.buyer.user', 'photos'])
            ->where('FRM_STATUS', 'PENDING_REVIEW')
            ->orderBy('FRM_CREATED_AT', 'asc')
            ->get();

        return response()->json([
            'farms' => $farms,
        ]);
    }

    /**
     * Approve a pending seller request: flip the farm to APPROVED + pin active
     * and mark the owning farmer/user as an active seller. Rejects if the farm
     * doesn't exist or isn't pending (avoids double-processing).
     */
    public function approve($farmId)
    {
        $farm = Farm::with('farmer.buyer.user')
            ->where('FRM_ID', $farmId)
            ->where('FRM_STATUS', 'PENDING_REVIEW')
            ->first();

        if (! $farm) {
            return response()->json([
                'message' => 'Farm not found or not pending review.',
            ], 404);
        }

        $farmer = $farm->farmer;
        $user = $farmer->buyer->user ?? null;

        try {
            DB::transaction(function () use ($farm, $farmer, $user) {
                $farm->FRM_STATUS = 'APPROVED';
                $farm->FRM_PIN_ACTIVE = 1;
                $farm->save();

                $farmer->FMR_SELLER_MODE_ACTIVE = 1;
                $farmer->FMR_VERIFIED_AT = $farmer->FMR_VERIFIED_AT ?? now();
                $farmer->save();

                if ($user) {
                    $user->USR_IS_SELLER = 1;
                    $user->save();
                }
            });
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'Failed to approve seller request.',
            ], 500);
        }

        // This is the second way a farm goes live: a non-whitelisted farmer submits
        // PENDING_REVIEW and an admin approves it here. Same notification as the
        // instant-approval path in FarmController@store, and the same
        // first-vs-additional test — is this the farmer's earliest farm?
        $isFirstFarm = $farmer->farms()
            ->orderBy('FRM_CREATED_AT')
            ->orderBy('FRM_ID')
            ->first()?->FRM_ID === $farm->FRM_ID;

        if ($user) {
            try {
                app(NotificationService::class)->notifyFarmLive(
                    $user->USR_ID,
                    $farm->FRM_ID,
                    $farm->FRM_NAME,
                    $isFirstFarm,
                );
            } catch (\Throwable $e) {
                // The approval itself has already committed. Losing the
                // notification is regrettable; unwinding the approval because
                // OneSignal was down would leave a farm the admin rejected.
                Log::warning('[notifications] farm-live notification failed', [
                    'usr_id' => $user->USR_ID,
                    'farm_id' => $farm->FRM_ID,
                    'message' => $e->getMessage(),
                ]);
            }
        }

        return response()->json([
            'message' => 'Seller request approved.',
            'farm_id' => $farm->FRM_ID,
            'frm_status' => 'APPROVED',
        ]);
    }

    /**
     * Reject a pending seller request: flips FRM_STATUS to REJECTED without
     * touching the owner's seller flags (a rejected user stays a plain buyer).
     * Accepts an optional reason, but there is no column to persist it for now.
     */
    public function reject($farmId, Request $request)
    {
        $farm = Farm::with('farmer.buyer.user')
            ->where('FRM_ID', $farmId)
            ->where('FRM_STATUS', 'PENDING_REVIEW')
            ->first();

        if (! $farm) {
            return response()->json([
                'message' => 'Farm not found or not pending review.',
            ], 404);
        }

        // Optional reason accepted but not persisted (no reason column yet).
        $request->validate([
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        try {
            DB::transaction(function () use ($farm) {
                $farm->FRM_STATUS = 'REJECTED';
                $farm->save();
            });
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'Failed to reject seller request.',
            ], 500);
        }

        return response()->json([
            'message' => 'Seller request rejected.',
            'farm_id' => $farm->FRM_ID,
            'frm_status' => 'REJECTED',
        ]);
    }
}
