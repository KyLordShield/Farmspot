<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Listing;
use Illuminate\Http\Request;

class FarmerListingController extends Controller
{
    /**
     * List ALL listings belonging to the authenticated farmer — any
     * LST_STATUS / LST_AVAILABILITY (unlike the buyer-facing feed which is
     * active-only). Includes the farm and category relations.
     */
    public function myListings(Request $request)
    {
        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer) {
            return response()->json([
                'message' => 'No farmer account found.',
            ], 403);
        }

        $listings = Listing::with(['farm', 'category'])
            ->where('FMR_ID', $farmer->FMR_ID)
            ->orderByDesc('LST_CREATED_AT')
            ->get()
            ->map(fn ($listing) => $this->formatListing($listing));

        return response()->json(['listings' => $listings]);
    }

    /**
     * Update just the LST_STATUS of one of the farmer's own listings.
     * Resets LST_EXPIRY_DATE to now()+3 days (expiry resets on any update),
     * per the capstone's rule.
     */
    public function updateStatus(Request $request, $listingId)
    {
        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer) {
            return response()->json([
                'message' => 'No farmer account found.',
            ], 403);
        }

        $listing = Listing::with(['farm', 'category'])
            ->where('LST_ID', $listingId)
            ->where('FMR_ID', $farmer->FMR_ID)
            ->first();

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found or does not belong to you.',
            ], 403);
        }

        $validated = $request->validate([
            'status' => ['required', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
        ]);

        $listing->LST_STATUS = $validated['status'];
        $listing->LST_EXPIRY_DATE = now()->addDays(3);
        $listing->LST_UPDATED_AT = now();
        $listing->save();

        return response()->json([
            'message' => 'Listing status updated successfully.',
            'listing' => $this->formatListing($listing),
        ]);
    }

    /**
     * Shape a Listing model into the same flat JSON structure the buyer feed
     * uses, so the farmer-facing screens share a consistent contract.
     */
    private function formatListing(Listing $listing): array
    {
        return [
            'id' => $listing->LST_ID,
            'crop_icon' => $listing->LST_CROP_ICON,
            'status' => $listing->LST_STATUS,
            'availability' => $listing->LST_AVAILABILITY,
            'harvest_date' => $listing->LST_HARVEST_DATE,
            'expiry_date' => $listing->LST_EXPIRY_DATE,
            'image' => $listing->LST_IMAGE,
            'created_at' => $listing->LST_CREATED_AT,
            'category' => [
                'id' => $listing->category->CAT_ID ?? null,
                'name' => $listing->category->CAT_NAME ?? null,
                'icon' => $listing->category->CAT_ICON ?? null,
            ],
            'farm' => [
                'id' => $listing->farm->FRM_ID ?? null,
                'name' => $listing->farm->FRM_NAME ?? null,
                'barangay' => $listing->farm->FRM_BARANGAY ?? null,
            ],
        ];
    }
}
