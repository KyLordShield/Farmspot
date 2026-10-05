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
                // The farmer id is what the app reports when a buyer flags the
                // seller rather than the crop, so it has to be reachable from
                // here. A buyer who could only reach the seller's name would
                // have no way to file the report.
                'id' => $listing->farmer?->FMR_ID,
                'name' => $farmerUser->USR_NAME ?? null,
                'mobile_number' => $farmerUser->USR_MOBILE_NUMBER ?? null,
            ];
        }

        // Rating summary, added to the payload only when the caller asked for
        // it with Listing::withRatingSummary(). Checking for the loaded
        // aggregates rather than defaulting them means an endpoint that does
        // not opt in keeps its exact previous shape, and no endpoint can
        // silently report "0.0 stars" for a listing it never actually counted.
        if (isset($listing->rating_count)) {
            $data['rating_average'] = $this->formatRatingAverage($listing->rating_average);
            $data['rating_count'] = (int) $listing->rating_count;
        }

        return $data;
    }

    /**
     * One review endpoint's average as a number rounded to one decimal, or null
     * when nobody has reviewed yet.
     *
     * Null rather than 0 is the point: "no reviews" and "reviewed and scored
     * zero" are different states, and a 0.0 would read as a terrible listing
     * instead of an unreviewed one. The app renders nothing at all for null.
     */
    protected function formatRatingAverage($average): ?float
    {
        if ($average === null || $average === '') {
            return null;
        }

        return round((float) $average, 1);
    }
}
