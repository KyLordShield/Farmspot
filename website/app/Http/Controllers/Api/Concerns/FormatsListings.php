<?php

namespace App\Http\Controllers\Api\Concerns;

use App\Models\Listing;

/**
 * Single source of truth for the flat listing JSON contract shared by every
 * endpoint that returns a listing (buyer feed, my-listings, farm profile,
 * create/update, photo management).
 *
 * `image` is kept for backward compatibility — it mirrors LST_IMAGE, the
 * denormalized cache of the current primary photo — while `photos` is the
 * full gallery: [{id, url, is_primary}], oldest-first.
 */
trait FormatsListings
{
    protected function formatListing(Listing $listing): array
    {
        $data = [
            'id' => $listing->LST_ID,
            'crop_icon' => $listing->LST_CROP_ICON,
            'status' => $listing->LST_STATUS,
            'availability' => $listing->LST_AVAILABILITY,
            'harvest_date' => $listing->LST_HARVEST_DATE,
            'expiry_date' => $listing->LST_EXPIRY_DATE,
            'description' => $listing->LST_DESCRIPTION,
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
            'photos' => $listing->photos
                ->map(fn ($photo) => [
                    'id' => $photo->LPHOTO_ID,
                    'url' => $photo->LPHOTO_FILE_PATH,
                    'is_primary' => (bool) $photo->LPHOTO_IS_PRIMARY,
                ])
                ->values(),
        ];

        // The buyer feed additionally loads the farmer's name/mobile number
        // up the nested relationship chain; only emit it when that relation
        // was actually requested, keeping the other endpoints' shape unchanged.
        if ($listing->relationLoaded('farmer')) {
            $farmerUser = $listing->farmer?->buyer?->user;

            $data['farmer'] = [
                'name' => $farmerUser->USR_NAME ?? null,
                'mobile_number' => $farmerUser->USR_MOBILE_NUMBER ?? null,
            ];
        }

        return $data;
    }
}
