<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Listing;
use Illuminate\Http\Request;

class ListingController extends Controller
{
    /**
     * Browse feed — active listings only, buyer-facing.
     */
    public function index(Request $request)
    {
        $search = $request->query('search');

        $listings = Listing::with(['farm', 'category', 'farmer.buyer.user'])
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->when($search, function ($query, $search) {
                $query->where(function ($q) use ($search) {
                    $q->whereHas('farm', function ($fq) use ($search) {
                        $fq->where('FRM_NAME', 'LIKE', "%{$search}%");
                    })->orWhereHas('category', function ($cq) use ($search) {
                        $cq->where('CAT_NAME', 'LIKE', "%{$search}%");
                    });
                });
            })
            ->orderByDesc('LST_CREATED_AT')
            ->get()
            ->map(fn ($listing) => $this->formatListing($listing));

        return response()->json([
            'listings' => $listings,
        ]);
    }

    /**
     * Single listing detail.
     */
    public function show($id)
    {
        $listing = Listing::with(['farm', 'category', 'farmer.buyer.user'])
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->find($id);

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found.',
            ], 404);
        }

        return response()->json([
            'listing' => $this->formatListing($listing),
        ]);
    }

    /**
     * Shape a Listing model into the flat JSON structure Flutter expects,
     * pulling the farmer's name/mobile number up from the nested relationship chain.
     */
    private function formatListing(Listing $listing): array
    {
        $farmerUser = $listing->farmer?->buyer?->user;

        return [
            'id' => $listing->LST_ID,
            'crop_icon' => $listing->LST_CROP_ICON,
            'status' => $listing->LST_STATUS,
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
                'latitude' => $listing->farm->FRM_LATITUDE ?? null,
                'longitude' => $listing->farm->FRM_LONGITUDE ?? null,
            ],
            'farmer' => [
                'name' => $farmerUser->USR_NAME ?? null,
                'mobile_number' => $farmerUser->USR_MOBILE_NUMBER ?? null,
            ],
        ];
    }
}