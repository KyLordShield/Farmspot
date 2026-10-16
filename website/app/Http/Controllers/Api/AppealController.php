<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Listing;
use App\Models\ReviewRequest;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Appeal submission endpoints for mobile.
 *
 * A listing that was taken down (REMOVED + LST_TAKEDOWN_REASON) can be appealed
 * by its owner. An account that was deactivated with a takedown reason can be
 * appealed by its owner using email and password, because the app is denied
 * access at login.
 *
 * One pending appeal per target. A DENIED appeal stays denied until a new
 * takedown — compared against the target's takedown timestamp — so a repeat
 * attempt against the same takedown is refused. No appeal for farmer-deleted
 * listings (no takedown reason).
 */
class AppealController extends Controller
{
    /**
     * Appeal a listing that was taken down.
     *
     * POST /api/listings/{listing}/appeal
     */
    public function storeListing(Request $request, string $listingId)
    {
        $user = $request->user();

        $listing = Listing::where('LST_ID', $listingId)->first();

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found.',
            ], 404);
        }

        // Only the owner can appeal their own listing.
        $ownerId = $listing->farmer?->buyer?->user?->USR_ID;
        if (! $ownerId || $ownerId !== $user->USR_ID) {
            return response()->json([
                'message' => 'You do not have permission to appeal this listing.',
            ], 403);
        }

        // Only a takedown — not a farmer-deleted listing — is appealable.
        if (! $listing->isTakenDown()) {
            return response()->json([
                'message' => 'This listing is not appealable.',
            ], 403);
        }

        // One pending appeal per target.
        $latest = ReviewRequest::latestFor(ReviewRequest::TARGET_LISTING, $listing->LST_ID);
        if ($latest && $latest->isPending()) {
            return response()->json([
                'message' => 'There is already a pending appeal for this listing.',
            ], 422);
        }

        // A denial is final until a new takedown happens. Compare against the
        // takedown timestamp recorded on the listing.
        if ($latest && $latest->RRQ_STATUS === ReviewRequest::STATUS_DENIED && $listing->LST_TAKEDOWN_AT) {
            if ($latest->RRQ_DECIDED_AT && $latest->RRQ_DECIDED_AT >= $listing->LST_TAKEDOWN_AT) {
                return response()->json([
                    'message' => 'A previous appeal was denied for this takedown.',
                ], 422);
            }
        }

        $validated = $request->validate([
            'reason' => ['nullable', 'string', 'max:2000'],
        ]);

        $appeal = ReviewRequest::create([
            'RRQ_ID' => ReviewRequest::newId(),
            'USR_ID' => $user->USR_ID,
            'RRQ_TARGET_TYPE' => ReviewRequest::TARGET_LISTING,
            'RRQ_TARGET_ID' => $listing->LST_ID,
            'RRQ_REASON' => $validated['reason'] ?? null,
            'RRQ_STATUS' => ReviewRequest::STATUS_PENDING,
            'RRQ_CREATED_AT' => now(),
        ]);

        return response()->json([
            'message' => 'Appeal submitted. An admin will review it.',
            'appeal_id' => $appeal->RRQ_ID,
        ], 201);
    }

    /**
     * Appeal a deactivated account. Authenticated by email + password (login
     * was refused because the account is taken down).
     *
     * POST /api/appeals/account
     */
    public function storeAccount(Request $request)
    {
        $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'reason' => ['nullable', 'string', 'max:2000'],
        ]);

        // Throttle: prevent brute-force attempts against deactivated accounts.
        $key = 'account_appeal:'.$request->ip().':'.Str::lower((string) $request->email);
        $attempts = cache()->get($key, 0);
        if ($attempts >= 5) {
            return response()->json([
                'message' => 'Too many attempts. Try again later.',
            ], 429);
        }
        cache()->put($key, $attempts + 1, 60);

        $user = User::where('USR_EMAIL', $request->email)->first();

        if (! $user || ! Hash::check($request->password, $user->USR_PASSWORD)) {
            return response()->json([
                'message' => 'Invalid credentials.',
            ], 401);
        }

        // Only a taken-down account (deactivated WITH a reason) may appeal.
        if (! $user->isTakenDown()) {
            return response()->json([
                'message' => 'This account is not appealable.',
            ], 403);
        }

        // One pending appeal per target.
        $latest = ReviewRequest::latestFor(ReviewRequest::TARGET_USER, $user->USR_ID);
        if ($latest && $latest->isPending()) {
            cache()->put($key, max(0, $attempts - 1), 60);
            return response()->json([
                'message' => 'There is already a pending appeal for this account.',
            ], 422);
        }

        // Denial final until a new takedown.
        if ($latest && $latest->RRQ_STATUS === ReviewRequest::STATUS_DENIED && $user->USR_TAKEDOWN_AT) {
            if ($latest->RRQ_DECIDED_AT && $latest->RRQ_DECIDED_AT >= $user->USR_TAKEDOWN_AT) {
                cache()->put($key, max(0, $attempts - 1), 60);
                return response()->json([
                    'message' => 'A previous appeal was denied for this takedown.',
                ], 422);
            }
        }

        $appeal = ReviewRequest::create([
            'RRQ_ID' => ReviewRequest::newId(),
            'USR_ID' => $user->USR_ID,
            'RRQ_TARGET_TYPE' => ReviewRequest::TARGET_USER,
            'RRQ_TARGET_ID' => $user->USR_ID,
            'RRQ_REASON' => $request->reason ?? null,
            'RRQ_STATUS' => ReviewRequest::STATUS_PENDING,
            'RRQ_CREATED_AT' => now(),
        ]);

        cache()->put($key, max(0, $attempts - 1), 60);

        return response()->json([
            'message' => 'Appeal submitted. An admin will review it.',
            'appeal_id' => $appeal->RRQ_ID,
        ], 201);
    }
}
