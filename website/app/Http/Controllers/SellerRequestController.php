<?php

namespace App\Http\Controllers;

use App\Models\Farm;
use App\Services\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class SellerRequestController extends Controller
{
    /**
     * List all farms awaiting review (FRM_STATUS = 'PENDING_REVIEW'), oldest
     * first, eager-loading the applicant's user details and the farm's photos.
     * Supports the same ?search= pattern as the whitelist screen (search by
     * farm name or owner name).
     */
    public function index(Request $request)
    {
        $sellerRequests = Farm::with(['farmer.buyer.user', 'photos'])
            ->where('FRM_STATUS', 'PENDING_REVIEW')
            ->when($request->filled('search'), function ($query) use ($request) {
                $query->where(function ($q) use ($request) {
                    $search = '%' . $request->search . '%';
                    $q->where('FRM_NAME', 'like', $search)
                      ->orWhereHas('farmer.buyer.user', function ($u) use ($search) {
                          $u->where('USR_NAME', 'like', $search);
                      });
                });
            })
            ->orderBy('FRM_CREATED_AT', 'asc')
            ->paginate(10)
            ->withQueryString();

        return view('seller-requests', compact('sellerRequests'));
    }

    /**
     * Show a single farm's full details for review (any status, but in practice
     * the pending ones), including photos and the verification document path.
     */
    public function show($farmId)
    {
        $farm = Farm::with(['farmer.buyer.user', 'photos'])
            ->where('FRM_ID', $farmId)
            ->firstOrFail();

        return view('seller-requests.show', compact('farm'));
    }

    /**
     * Approve a pending seller request: flip the farm to APPROVED + pin active
     * and mark the owning farmer/user as an active seller. Redirects back with
     * a success flash message.
     */
    public function approve($farmId)
    {
        $farm = Farm::with('farmer.buyer.user')
            ->where('FRM_ID', $farmId)
            ->where('FRM_STATUS', 'PENDING_REVIEW')
            ->first();

        if (! $farm) {
            return redirect()->route('seller-requests')
                ->with('error', 'Farm not found or not pending review.');
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
            return redirect()->route('seller-requests')
                ->with('error', 'Failed to approve seller request.');
        }

        // This is the path a moderator actually uses: the admin panel posts to
        // the web route, not the API one. The approval had been happening here
        // with no notification at all, so the seller was told they were a farmer
        // by nothing - no inbox row, no push, and no way to find out.
        //
        // Routed through the same NotificationService::notifyFarmLive() the API
        // controller uses, deliberately: the wording lives in one place, and the
        // de-duplication is on the farm id, so even if both routes somehow ran
        // for the same farm the farmer is told once rather than twice.
        if ($user) {
            try {
                $isFirstFarm = $farmer->farms()
                    ->orderBy('FRM_CREATED_AT')
                    ->orderBy('FRM_ID')
                    ->first()?->FRM_ID === $farm->FRM_ID;

                app(NotificationService::class)->notifyFarmLive(
                    $user->USR_ID,
                    $farm->FRM_ID,
                    $farm->FRM_NAME,
                    $isFirstFarm,
                );
            } catch (\Throwable $e) {
                // The approval is already committed. A moderator who sees this
                // request fail would reasonably try approving again, and the
                // second attempt would be rejected as "not pending review".
                Log::warning('[notifications] farm-live notification failed', [
                    'usr_id' => $user->USR_ID,
                    'farm_id' => $farm->FRM_ID,
                    'message' => $e->getMessage(),
                ]);
            }
        }

        return redirect()->route('seller-requests')
            ->with('success', "Seller request for \"{$farm->FRM_NAME}\" approved successfully.");
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
            return redirect()->route('seller-requests')
                ->with('error', 'Farm not found or not pending review.');
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
            return redirect()->route('seller-requests')
                ->with('error', 'Failed to reject seller request.');
        }

        return redirect()->route('seller-requests')
            ->with('success', "Seller request for \"{$farm->FRM_NAME}\" rejected.");
    }
}
