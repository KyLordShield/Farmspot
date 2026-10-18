<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\SearchHelpers;
use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Models\Listing;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * One-shot buyer search used by the app's search screen and its results
 * previews.
 *
 * The plain crop search lives on GET /api/listings (?search=) and keeps owning
 * the search_log insert. This endpoint is deliberately side-effect free: it is
 * called on every debounced keystroke, so it must never write analytics, and it
 * returns the farm and seller matches the listings endpoint cannot — a farm or a
 * person is not a listing, and the buyer needs to see all three before deciding
 * what they meant.
 *
 * The farm and seller sets are restricted to farms that actually have a public
 * listing, so the previews never advertise a farm or seller the crop grid
 * below them would not show.
 */
class SearchController extends Controller
{
    use SearchHelpers;

    /**
     * GET /api/search?q=<term>&limit=<n>
     *
     * Returns crops (name + count), farms and sellers that match the term.
     * An empty term yields three empty lists rather than an unbounded scan.
     */
    public function index(Request $request)
    {
        $search = trim((string) $request->query('q', $request->query('search', '')));
        $limit = $this->searchLimit($request->query('limit'), 8);

        if ($search === '') {
            return response()->json([
                'crops' => [],
                'farms' => [],
                'sellers' => [],
            ]);
        }

        return response()->json([
            'crops' => $this->cropSuggestions($search, $limit),
            'farms' => $this->farmsMatching($search, $limit),
            'sellers' => $this->sellersMatching($search, $limit),
        ]);
    }

    /**
     * Crop names (with a count of matching listings) drawn from the same
     * keyword match the crop grid uses, so a suggestion is always a term that
     * would return results. Mirrors the app's old client-side derivation of
     * suggestions from the /listings response.
     */
    private function cropSuggestions(string $search, int $limit): array
    {
        $listings = Listing::with('category')
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->where('LST_STATUS', '!=', 'NOT_AVAILABLE')
            ->where(fn ($query) => $this->applyKeyword($query, $search))
            ->get(['LST_ID', 'LST_CROP_ICON', 'CAT_ID']);

        $lower = Str::lower($search);
        $counts = [];

        foreach ($listings as $listing) {
            // The seller-typed crop name wins; the category label is the
            // fallback for older rows with no name, exactly as the feed does.
            $name = trim((string) ($listing->LST_CROP_ICON ?: ($listing->category->CAT_NAME ?? '')));

            // The match can have come from the farm/seller/description rather
            // than the crop name, so re-check the name before offering it.
            if ($name === '' || ! Str::contains(Str::lower($name), $lower)) {
                continue;
            }

            $counts[$name] = ($counts[$name] ?? 0) + 1;
        }

        $pairs = [];
        foreach ($counts as $name => $count) {
            $pairs[] = ['name' => $name, 'count' => $count];
        }

        usort($pairs, fn ($a, $b) => ($b['count'] <=> $a['count']) ?: strcmp($a['name'], $b['name']));

        return array_slice($pairs, 0, $limit);
    }

    /**
     * Approved, pin-active farms matching by name or barangay that still have
     * at least one public listing.
     */
    private function farmsMatching(string $search, int $limit): array
    {
        return Farm::with(['photos' => fn ($query) => $query->orderBy('FPHOTO_UPLOADED_AT')])
            ->withCount([
                'listings as active_listings_count' => function ($query) {
                    $query->where('LST_STATUS', 'AVAILABLE_NOW')
                        ->where('LST_AVAILABILITY', 'ACTIVE');
                },
            ])
            ->where('FRM_STATUS', 'APPROVED')
            ->where('FRM_PIN_ACTIVE', 1)
            ->where(function ($query) use ($search) {
                $query->where('FRM_NAME', 'LIKE', "%{$search}%")
                    ->orWhere('FRM_BARANGAY', 'LIKE', "%{$search}%");
            })
            ->whereHas('listings', function ($query) {
                $query->where('LST_AVAILABILITY', 'ACTIVE')
                    ->where('LST_STATUS', '!=', 'NOT_AVAILABLE');
            })
            ->orderByDesc('active_listings_count')
            ->orderBy('FRM_NAME')
            ->limit($limit)
            ->get()
            ->map(fn ($farm) => $this->farmCard($farm))
            ->all();
    }

    /**
     * The keyword group every search surface shares: crop name, farm name,
     * category, description and seller name.
     */
    private function applyKeyword($query, string $search): void
    {
        $query->where('LST_CROP_ICON', 'LIKE', "%{$search}%")
            ->orWhereHas('farm', fn ($q) => $q->where('FRM_NAME', 'LIKE', "%{$search}%"))
            ->orWhereHas('category', fn ($q) => $q->where('CAT_NAME', 'LIKE', "%{$search}%"))
            ->orWhere('LST_DESCRIPTION', 'LIKE', "%{$search}%")
            ->orWhereHas('farmer.buyer.user', fn ($q) => $q->where('USR_NAME', 'LIKE', "%{$search}%"));
    }
}
