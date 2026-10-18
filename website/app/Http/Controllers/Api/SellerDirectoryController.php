<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\FormatsListings;
use App\Http\Controllers\Api\Concerns\SearchHelpers;
use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\ListingReview;
use Illuminate\Http\Request;

/**
 * Buyer-facing seller directory.
 *
 *   GET /api/sellers?search=<term>   search sellers by account name
 *   GET /api/sellers/{farmerId}      one seller's public profile
 *
 * A "seller" is a farmer record (FMR_ID): that is the identity the rest of the
 * app already reports against when a buyer flags the person rather than the
 * crop, and the one an account with several farms is grouped under. The display
 * name comes from the linked user account (USR_NAME) and is nullable, so a
 * farmer with no linked account is omitted rather than shown as a blank row.
 */
class SellerDirectoryController extends Controller
{
    use FormatsListings;
    use SearchHelpers;

    /**
     * GET /api/sellers?search=<term>&limit=<n>
     */
    public function index(Request $request)
    {
        $search = trim((string) $request->query('search', $request->query('q', '')));
        $limit = $this->searchLimit($request->query('limit'), 20);

        return response()->json([
            'sellers' => $this->sellersMatching($search, $limit),
        ]);
    }

    /**
     * GET /api/sellers/{farmerId}
     *
     * The seller's public farms and every listing buyers can see, plus a
     * whole-seller rating averaged across the VISIBLE reviews on those
     * listings — the same visible-only rule the farm profile uses.
     */
    public function show(Request $request, $farmerId)
    {
        $farmer = Farmer::with('buyer.user')->find($farmerId);

        if (! $farmer) {
            return response()->json([
                'message' => 'Seller not found.',
            ], 404);
        }

        // Only farms that are actually on the buyer map (approved + pin-active)
        // and that still carry at least one public listing, so the profile
        // never opens onto an empty farm.
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
            ->whereHas('listings', function ($query) {
                $query->where('LST_AVAILABILITY', 'ACTIVE')
                    ->where('LST_STATUS', '!=', 'NOT_AVAILABLE');
            })
            ->orderByDesc('FRM_CREATED_AT')
            ->get();

        // NOT_AVAILABLE stays visible (a sold-out crop is still this seller's
        // story), but a moderator-REMOVED listing must not leave the wall.
        $listings = Listing::with(['category', 'farm', 'farmer.buyer.user', 'photos'])
            ->withRatingSummary()
            ->where('FMR_ID', $farmer->FMR_ID)
            ->where('LST_AVAILABILITY', '!=', Listing::AVAILABILITY_REMOVED)
            ->whereHas('farm', function ($query) {
                $query->where('FRM_STATUS', 'APPROVED')
                    ->where('FRM_PIN_ACTIVE', 1);
            })
            ->orderByRaw("FIELD(LST_STATUS, 'AVAILABLE_NOW', 'SOON_TO_HARVEST', 'NOT_AVAILABLE')")
            ->orderByDesc('LST_CREATED_AT')
            ->get()
            ->map(fn ($listing) => $this->formatListing($listing));

        $rating = ListingReview::whereHas('listing', function ($query) use ($farmer) {
            $query->where('FMR_ID', $farmer->FMR_ID);
        })
            ->visible()
            ->selectRaw('AVG(LRV_RATING) AS rating_avg, COUNT(*) AS rating_count')
            ->first();

        $name = trim((string) $farmer->buyer?->user?->USR_NAME);

        return response()->json([
            'seller' => [
                'id' => $farmer->FMR_ID,
                'user_id' => $farmer->buyer?->user?->USR_ID,
                'name' => $name === '' ? null : $name,
                'photo_url' => $farmer->buyer?->user?->USR_PHOTO_PATH,
                'farm_count' => $farms->count(),
                'active_listings_count' => (int) $farms->sum('active_listings_count'),
            ],
            'farms' => $farms->map(fn ($farm) => $this->farmCard($farm))->values(),
            'listings' => $listings,
            'rating_average' => $rating?->rating_avg === null
                ? null
                : round((float) $rating->rating_avg, 2),
            'rating_count' => (int) ($rating->rating_count ?? 0),
        ]);
    }
}
