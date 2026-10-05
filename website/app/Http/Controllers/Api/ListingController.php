<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\FormatsListings;
use App\Http\Controllers\Api\Concerns\RanksFeedListings;
use App\Http\Controllers\Controller;
use App\Models\ContactLog;
use App\Models\CropCategory;
use App\Models\Listing;
use App\Models\SearchLog;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class ListingController extends Controller
{
    use FormatsListings;
    use RanksFeedListings;

    /**
     * Catalog of all crop categories. Simple, unfiltered list — no farmer
     * association needed.
     */
    public function cropCategories()
    {
        $categories = CropCategory::orderBy('CAT_NAME')->get()->map(
            fn ($c) => [
                'id' => $c->CAT_ID,
                'name' => $c->CAT_NAME,
                'icon' => $c->CAT_ICON,
                'description' => $c->CAT_DESCRIPTION,
            ]
        );

        return response()->json(['categories' => $categories]);
    }
    /**
     * Browse feed — active listings only, buyer-facing.
     *
     * Also logs a search_log row whenever a non-empty ?search= is used by an
     * authenticated user. Plain feed loads (no keyword) and unauthenticated
     * browsing are NOT logged, so guest browsing keeps working with zero
     * side effects.
     *
     * Two opt-in parameters, independent of each other and both off by default:
     *
     *   ?page / ?per_page   return one page instead of the whole active set
     *   ?personalized=1     order the page by rating, discovery and history
     *
     * Neither is sent by the app's search or suggestion requests, so those keep
     * receiving exactly the response they received before — see RanksFeedListings
     * for why the ordering lives on the server.
     */
    public function index(Request $request)
    {
        $search = $request->query('search');

        // Feed filters. Every value is whitelisted rather than interpolated, so
        // a hand-typed ?sort= drops the sort instead of reaching the ORDER BY,
        // and an unknown category simply matches nothing.
        $category = $request->query('category');
        $status = $request->query('status');

        // LST_STATUS is an enum, so these are the only two reachable values on
        // the public feed: the query below already excludes NOT_AVAILABLE, and
        // listings:expire has moved every past-due row out of circulation.
        $allowedStatuses = ['AVAILABLE_NOW', 'SOON_TO_HARVEST'];
        $allowedSorts = ['latest', 'date', 'popular'];
        $sort = in_array($request->query('sort'), $allowedSorts, true)
            ? $request->query('sort')
            : 'latest';

        // Paging and ranking are separate decisions, and they are read BEFORE the
        // query runs because both of them change how that query is built and
        // executed. A request that sends neither is the shape every existing
        // caller already depends on, and it falls through to the original path
        // below untouched.
        $paging = $this->readFeedPaging($request);
        $personalized = $request->query('personalized') === '1';

        // /listings is a PUBLIC route (no auth middleware), so the optional
        // Sanctum user is resolved explicitly: a valid Bearer token present on
        // the request gets resolved, guests stay null. This has to happen before
        // the query is built, because ranking reads this user's search history.
        $user = $request->user('sanctum');

        // withRatingSummary() folds the average + count into this same query as
        // two subqueries, so rating_average / rating_count reach every card on
        // the feed at the cost of nothing extra per listing.
        $query = Listing::with(['farm', 'category', 'farmer.buyer.user', 'photos'])
            ->withRatingSummary()
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->where('LST_STATUS', '!=', 'NOT_AVAILABLE')
            ->when($search, function ($query, $search) {
                $query->where(function ($q) use ($search) {
                    $q->where('LST_CROP_ICON', 'LIKE', "%{$search}%")
                        ->orWhereHas('farm', function ($fq) use ($search) {
                            $fq->where('FRM_NAME', 'LIKE', "%{$search}%");
                        })->orWhereHas('category', function ($cq) use ($search) {
                            $cq->where('CAT_NAME', 'LIKE', "%{$search}%");
                        })->orWhere('LST_DESCRIPTION', 'LIKE', "%{$search}%");
                });
            })
            ->when($category, fn ($q) => $q->where('CAT_ID', $category))
            ->when(
                in_array($status, $allowedStatuses, true),
                fn ($q) => $q->where('LST_STATUS', $status)
            );

        // Each sort needs a different leading column, and only "popular" needs
        // a join, so the three are built separately rather than through one
        // switch. Contacts are counted in a subquery instead of an eager load,
        // which keeps this to a single query.
        //
        // This is a closure rather than inline ordering because the same three
        // orders have to be reusable: whole feed when nothing is paged, one page
        // when it is. LST_ID is the last key on all of them so that two pages of
        // one sort can never hand the same listing to both — without a total
        // tiebreaker, MySQL is free to return equal rows in a different order
        // per query, and a listing would be skipped or duplicated across pages.
        $order = function ($builder) use ($sort) {
            if ($sort === 'popular') {
                return $builder
                    ->withCount('contacts')
                    ->orderByDesc('contacts_count')
                    // A tie should not shuffle between refreshes, and neither
                    // should two listings that nobody has contacted yet.
                    ->orderByDesc('LST_CREATED_AT')
                    ->orderBy('LST_ID');
            }

            if ($sort === 'date') {
                // Soonest harvest first. NULLS LAST is spelled out because a
                // seller who has not set a harvest date should sink to the bottom
                // rather than lead the feed on a NULL.
                return $builder
                    ->orderByRaw('LST_HARVEST_DATE IS NULL, LST_HARVEST_DATE ASC')
                    ->orderByDesc('LST_CREATED_AT')
                    ->orderBy('LST_ID');
            }

            return $builder->orderByDesc('LST_CREATED_AT')->orderBy('LST_ID');
        };

        $pagination = null;

        if ($personalized) {
            // Ranked feed. An explicit ?sort= is deliberately NOT applied here:
            // asking for the ranked feed and asking for "soonest harvest first"
            // are different requests, and the app only sends both on purpose when
            // the buyer has not chosen a sort.
            [$rows, $lastPage, $poolTotal] = $this->rankAndSliceFeed(
                $query,
                $this->categoryAffinities($user),
                $paging['page'],
                $paging['perPage']
            );

            $listings = $rows->map(fn ($listing) => $this->formatListing($listing));

            // Pagination over a ranked feed describes the ranked candidate pool,
            // not every matching row in the table: the pool is what the page is
            // actually sliced from, so total and last_page have to agree with it
            // or the app computes a page count that does not exist.
            if ($paging['page'] !== null) {
                $pagination = [
                    'current_page' => $paging['page'],
                    'last_page' => $lastPage,
                    'per_page' => $paging['perPage'],
                    'total' => $poolTotal,
                ];
            }
        } elseif ($paging['page'] !== null) {
            // Paged but explicitly ordered — the buyer's chosen sort wins, and it
            // wins in SQL: count and slice both happen there, so the database
            // never sends rows the app is about to throw away.
            $paginator = $order(clone $query)->paginate(
                $paging['perPage'],
                ['*'],
                'page',
                $paging['page']
            );

            $listings = $paginator->getCollection()
                ->map(fn ($listing) => $this->formatListing($listing));

            $pagination = [
                'current_page' => $paginator->currentPage(),
                'last_page' => $paginator->lastPage(),
                'per_page' => $paginator->perPage(),
                'total' => $paginator->total(),
            ];
        } else {
            // The original path, unchanged: every active listing, ordered, no
            // pagination metadata.
            $listings = $order($query)->get()
                ->map(fn ($listing) => $this->formatListing($listing));
        }

        // The applied filters go into the analytics slot that already exists on
        // search_log, so "what do people actually filter by" is answerable
        // without a new table.
        $appliedFilters = array_filter([
            'category' => $category,
            'status' => $status,
            'sort' => $sort !== 'latest' ? $sort : null,
        ]);

        // Pure opt-out for ONE extra caller: the app's live "as you type"
        // suggestion requests send ?suggest=1, and those must NOT pollute the
        // Top Searched analytics the way keystrokes would. When the param is
        // absent — every existing caller, and every real submitted search from
        // the new Search screen — this branch is byte-for-byte identical to the
        // original: same insert, same fields, same counting.
        $isSuggestion = $request->query('suggest') === '1';

        if ($search && $user && !$isSuggestion) {
            do {
                $searchId = strtoupper(Str::random(6));
            } while (SearchLog::where('SRCH_ID', $searchId)->exists());

            SearchLog::create([
                'SRCH_ID' => $searchId,
                'SRCH_KEYWORD' => $search,
                'SRCH_FILTERS' => $request->query('filters')
                    ?: ($appliedFilters ? json_encode($appliedFilters) : null),
                'SRCH_CREATED_AT' => now(),
                'USR_ID' => $user->USR_ID,
            ]);
        }

        $body = ['listings' => $listings];

        if ($pagination !== null) {
            $body['pagination'] = $pagination;
        }

        return response()->json($body);
    }

    /**
     * Log a single contact action (CALL or SMS) against a listing for the
     * authenticated user. Every tap inserts one row — no deduplication.
     */
    public function logContact(Request $request, $listingId)
    {
        $validated = $request->validate([
            'method' => ['required', 'in:CALL,SMS'],
        ]);

        $listing = Listing::find($listingId);

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found.',
            ], 404);
        }

        do {
            $contactId = strtoupper(Str::random(6));
        } while (ContactLog::where('CTL_ID', $contactId)->exists());

        ContactLog::create([
            'CTL_ID' => $contactId,
            'USR_ID' => $request->user()->USR_ID,
            'LST_ID' => $listing->LST_ID,
            'CTL_METHOD' => $validated['method'],
            'CTL_CREATED_AT' => now(),
        ]);

        return response()->json([
            'message' => 'Contact logged.',
            'contact_id' => $contactId,
            'listing_id' => $listing->LST_ID,
            'method' => $validated['method'],
        ], 201);
    }

    /**
     * Single listing detail.
     */
    public function show($id)
    {
        $listing = Listing::with(['farm', 'category', 'farmer.buyer.user', 'photos'])
            ->withRatingSummary()
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->where('LST_STATUS', '!=', 'NOT_AVAILABLE')
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
}