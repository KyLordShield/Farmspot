<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Listing;
use App\Models\SearchLog;
use App\Models\Trend;
use Illuminate\Support\Facades\DB;

class InsightsController extends Controller
{
    private const TOP_N_SEARCHES = 4;

    private const TOP_N_CATEGORIES = 5;

    /**
     * Delivery endpoint for the Insights screen.
     *
     * Two of the three sections are computed LIVE on every request, straight
     * from the source tables:
     *   - "Top Searched This Week": a single cheap aggregate over
     *     search_log (7-day window). Counting at request time means a search
     *     you make right now shows up as soon as you open this screen — no
     *     need to wait for a batch job to re-run.
     *   - "Listings by Category": a similar aggregate over live listings, so
     *     new/removed listings are reflected immediately.
     *
     * Only "Seasonal Trends" comes from the `trend` table, because that one is
     * real data mining (Python computing month-of-harvest groupings); it's
     * genuinely expensive to redo per request.
     *
     * This keeps counter-style insights fresh while the Python pipeline owns
     * the analytical/heavier work.
     */
    public function show()
    {
        $topSearched = $this->topSearched();
        $byCategory = $this->byCategory();
        $trends = Trend::orderBy('TRND_PERIOD_MONTH')->get()->map(
            fn ($row) => [
                'period' => $row->TRND_PERIOD_MONTH,
                'title' => $row->TRND_TITLE,
                'crops' => json_decode($row->TRND_DATA, true),
            ]
        );

        return response()->json([
            'insights' => [
                [
                    'type' => 'top_searched',
                    'title' => 'Top Searched This Week',
                    'data' => $topSearched,
                ],
                [
                    'type' => 'by_category',
                    'title' => 'Listings by Category',
                    'data' => $byCategory,
                ],
            ],
            'seasonal_trends' => $trends,
        ]);
    }

    /**
     * Ranks crops by number of searches in the last 7 days.
     * Keyword case is normalized (lower-cased) so "Tomato" and "tomato" count
     * as the same crop — mirroring what step2_compute_insights.py does.
     */
    private function topSearched(): array
    {
        $rows = DB::table('search_log')
            ->where('SRCH_CREATED_AT', '>=', now()->subDays(7))
            ->whereNotNull('SRCH_KEYWORD')
            ->where('SRCH_KEYWORD', '!=', '')
            ->selectRaw('LOWER(TRIM(SRCH_KEYWORD)) as crop, COUNT(*) as count')
            ->groupBy('crop')
            ->orderByDesc('count')
            ->orderBy('crop')
            ->limit(self::TOP_N_SEARCHES)
            ->get();

        return collect($rows)->values()->map(
            fn ($row, $i) => [
                'rank' => $i + 1,
                'crop' => $row->crop,
                'count' => (int) $row->count,
            ]
        )->all();
    }

    /**
     * Counts currently-sellable listings per crop category, ranked.
     */
    private function byCategory(): array
    {
        $rows = Listing::join('crop_category', 'listing.CAT_ID', '=', 'crop_category.CAT_ID')
            ->whereIn('LST_STATUS', ['AVAILABLE_NOW', 'SOON_TO_HARVEST'])
            ->selectRaw('crop_category.CAT_NAME as category, COUNT(*) as listing_count')
            ->groupBy('category')
            ->orderByDesc('listing_count')
            ->orderBy('category')
            ->limit(self::TOP_N_CATEGORIES)
            ->get();

        return collect($rows)->values()->map(
            fn ($row, $i) => [
                'rank' => $i + 1,
                'category' => $row->category,
                'listing_count' => (int) $row->listing_count,
            ]
        )->all();
    }
}