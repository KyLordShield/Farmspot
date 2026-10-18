<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\SearchHelpers;
use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Models\ListingReview;
use App\Models\User;
use Illuminate\Http\Request;

/**
 * Public user profile for the buyer-facing app.
 *
 *   GET /api/users/{userId}/profile
 *
 * This is the person behind a farm, the other side of a chat, or a seller in
 * the search previews. It is keyed on the account (USR_ID) rather than the
 * farmer record on purpose: every profile has an account, while only a seller
 * has a farmer row, so the same screen can show a pure buyer's contact card and
 * a seller's contact card plus their farms.
 *
 * The payload is deliberately just the person: name, contact details, photo,
 * and — only when they actually run farms — the farm cards. There is no listing
 * wall here; the farm profile owns that.
 */
class UserProfileController extends Controller
{
    use SearchHelpers;

    public function show(Request $request, $userId)
    {
        $user = User::find($userId);

        if (! $user) {
            return response()->json([
                'message' => 'User not found.',
            ], 404);
        }

        $farmer = $user->buyer?->farmer;

        $farms = collect();
        $rating = null;

        if ($farmer) {
            // Every farm this person runs that is actually on the buyer map
            // (approved + pin-active). Deliberately NOT gated on having a
            // listing: the profile is where a buyer goes to see the whole seller,
            // and a farm with nothing in season is still that seller's farm.
            $farms = Farm::with(['photos' => fn ($query) => $query->orderBy('FPHOTO_UPLOADED_AT')])
                ->withCount([
                    'listings as active_listings_count' => function ($query) {
                        $query->where('LST_STATUS', 'AVAILABLE_NOW')
                            ->where('LST_AVAILABILITY', 'ACTIVE');
                    },
                ])
                ->where('FMR_ID', $farmer->FMR_ID)
                ->where('FRM_STATUS', 'APPROVED')
                ->where('FRM_PIN_ACTIVE', 1)
                ->orderByDesc('FRM_CREATED_AT')
                ->get();

            // Whole-seller rating, over the VISIBLE reviews on this seller's
            // listings — the same visible-only rule the farm profile uses.
            $rating = ListingReview::whereHas('listing', function ($query) use ($farmer) {
                $query->where('FMR_ID', $farmer->FMR_ID);
            })
                ->visible()
                ->selectRaw('AVG(LRV_RATING) AS rating_avg, COUNT(*) AS rating_count')
                ->first();
        }

        return response()->json([
            'user' => [
                'id' => $user->USR_ID,
                'name' => trim((string) $user->USR_NAME) ?: null,
                'address' => $user->USR_ADDRESS,
                'phone' => $user->USR_MOBILE_NUMBER,
                'photo' => $user->USR_PHOTO_PATH,
                // Whether this account runs any farm at all, so the badge and
                // the report target are decided from one place.
                'is_seller' => $farmer !== null,
                'farmer_id' => $farmer?->FMR_ID,
            ],
            'farms' => $farms->map(fn ($farm) => $this->farmCard($farm))->values(),
            'farm_count' => $farms->count(),
            'active_listings_count' => (int) $farms->sum('active_listings_count'),
            'rating_average' => $rating?->rating_avg === null
                ? null
                : round((float) $rating->rating_avg, 2),
            'rating_count' => (int) ($rating->rating_count ?? 0),
        ]);
    }
}
