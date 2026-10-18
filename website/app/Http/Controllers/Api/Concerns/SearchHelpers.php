<?php

namespace App\Http\Controllers\Api\Concerns;

use App\Models\Farm;
use App\Models\Listing;
use Illuminate\Support\Collection;

/**
 * Shared pieces of the buyer-facing search: the result cap, the seller
 * directory query, and the compact farm card.
 *
 * Kept in one place because /api/search (the combined preview) and
 * /api/sellers (the directory) must agree on what a "public seller" and a farm
 * card are, or the preview and the "See all" list would disagree about the
 * same term.
 */
trait SearchHelpers
{
    /**
     * Clamp a client-supplied result cap.
     *
     * The typeahead asks for a handful and "See all" asks for more, so the cap
     * is a parameter — but it is clamped to 1..50 so a hand-typed ?limit=
     * cannot turn a single search into an unbounded result set.
     */
    protected function searchLimit($value, int $default = 8): int
    {
        $limit = (int) $value;

        if ($limit <= 0) {
            return $default;
        }

        return min($limit, 50);
    }

    /**
     * Sellers whose account name matches $search and who currently have at
     * least one public listing on an approved, pin-active farm.
     *
     * Derived from the listings themselves rather than from the farmer table so
     * the directory can never list a seller with nothing to show, and so the
     * per-seller farm/listing counts describe exactly the buyer-visible set.
     * A farmer with no linked user account (or a blank name) is skipped.
     */
    protected function sellersMatching(string $search, int $limit): array
    {
        if (trim($search) === '') {
            return [];
        }

        $rows = Listing::query()
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->where('LST_STATUS', '!=', 'NOT_AVAILABLE')
            ->whereHas('farm', function ($query) {
                $query->where('FRM_STATUS', 'APPROVED')
                    ->where('FRM_PIN_ACTIVE', 1);
            })
            ->whereHas('farmer.buyer.user', function ($query) use ($search) {
                $query->where('USR_NAME', 'LIKE', "%{$search}%");
            })
            ->with(['farmer.buyer.user'])
            ->get();

        $sellers = $rows
            ->groupBy('FMR_ID')
            ->map(function (Collection $listings) {
                $farmer = $listings->first()->farmer;
                $user = $farmer?->buyer?->user;
                $name = trim((string) $user?->USR_NAME);

                if (! $farmer || $name === '') {
                    return null;
                }

                return [
                    'id' => $farmer->FMR_ID,
                    // The account behind the farmer. This is the key the buyer
                    // profile screen opens on, because a profile can also be a
                    // plain buyer (no farmer row) — the user id is the one
                    // identity every profile has.
                    'user_id' => $user->USR_ID,
                    'name' => $name,
                    // Real profile photo, so a seller looks the same in the
                    // search list as they do in the chat header and profile.
                    'photo_url' => $user->USR_PHOTO_PATH,
                    'farm_count' => $listings->pluck('FRM_ID')->unique()->count(),
                    // Same meaning as the map/farm card and the seller profile:
                    // AVAILABLE_NOW listings only, not merely "has a listing".
                    // The rows also include SOON_TO_HARVEST, so they must be
                    // filtered here or the directory would count 19 where the
                    // profile it opens says 18.
                    'active_listings_count' => $listings
                        ->where('LST_STATUS', 'AVAILABLE_NOW')
                        ->count(),
                ];
            })
            ->filter()
            ->values();

        // Most active seller first, then alphabetical, so identical counts
        // order stably instead of following row order.
        $sorted = $sellers->sortBy([
            fn ($a, $b) => $b['active_listings_count'] <=> $a['active_listings_count'],
            fn ($a, $b) => strcasecmp($a['name'], $b['name']),
        ]);

        return $sorted->take($limit)->values()->all();
    }

    /**
     * The compact farm card shared by the search previews and the seller
     * profile. Matches the shape GET /api/farms/public already returns for the
     * map, so a farm looks identical wherever it is listed. Requires the
     * `photos` relation and the `active_listings_count` count to be loaded.
     */
    protected function farmCard(Farm $farm): array
    {
        $primary = $farm->photos
            ->first(fn ($photo) => (int) $photo->FPHOTO_IS_PRIMARY === 1)
            ?? $farm->photos->first();

        return [
            'id' => $farm->FRM_ID,
            'name' => $farm->FRM_NAME,
            'barangay' => $farm->FRM_BARANGAY,
            'latitude' => $farm->FRM_LATITUDE,
            'longitude' => $farm->FRM_LONGITUDE,
            'active_listings_count' => (int) ($farm->active_listings_count ?? 0),
            'photo_url' => $primary?->FPHOTO_FILE_PATH,
        ];
    }
}
