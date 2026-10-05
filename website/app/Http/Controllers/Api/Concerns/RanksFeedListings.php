<?php

namespace App\Http\Controllers\Api\Concerns;

use App\Models\CropCategory;
use App\Models\Listing;
use App\Models\SearchLog;
use Illuminate\Http\Request;

/**
 * Ranking and paging for the buyer feed.
 *
 * The feed used to be "every active listing, newest first", which is fine at
 * five listings and not at several hundred: the whole active set crossed the
 * wire on every load, every refresh, every search and every suggestion
 * keystroke. This trait adds two opt-in behaviours behind explicit parameters
 * so that no existing caller changes shape:
 *
 *   ?page / ?per_page   1..30, clamped rather than rejected
 *   ?personalized=1     rank by rating, discovery and search history
 *
 * Both are off unless asked for. The app's search and suggestion requests do not
 * send them, so they keep receiving exactly the response they received before.
 *
 * WHY RANKING LIVES HERE AND NOT IN THE APP: the signals are server-side. A
 * client cannot rank by contact counts it was never sent, nor read search_log
 * rows that belong to a user it only knows by token. Ranking on the client would
 * also mean the client had already downloaded the thing it was supposed to be
 * avoiding, which defeats the paging.
 */
trait RanksFeedListings
{
    /**
     * The rating every listing starts with, before anyone has rated it.
     *
     * 3.5 is the midpoint of the 1..5 scale and is deliberately generous rather
     * than harsh: a new listing should be able to compete, not start in a hole
     * it has to climb out of on review counts it does not have yet.
     */
    protected const FEED_PRIOR_MEAN = 3.5;

    /**
     * How many ratings it takes to move a listing halfway from the prior toward
     * its real average.
     *
     * This is the whole point of the Bayesian average. "average x count" as a
     * naive popularity score says a 5.0 from one person beats a 4.6 from fifty,
     * which is one lucky tap outranking a well-reviewed crop. Here, a 5.0 with
     * one rating lands at 3.75 and a 4.6 with fifty lands at 4.5, so the crop
     * people have actually reviewed wins. It also means an unreviewed listing
     * scores exactly 3.5 rather than 0 — no ratings is not bad ratings.
     */
    protected const FEED_PRIOR_WEIGHT = 5.0;

    /**
     * The most contact activity is ever worth, in popularity points.
     *
     * Contacts stay a secondary signal, deliberately, and the way to keep them
     * secondary is a CAP rather than a small coefficient. ln() grows without
     * limit, so any coefficient big enough to break a dead heat eventually stops
     * being a nudge: at 0.25, twenty contacts added 0.76 to popularity and
     * carried an unreviewed listing past a crop with twelve five-star reviews.
     * That is ranking by contact volume wearing a different name, and it makes
     * discovery self-reinforcing — the listings already being contacted collect
     * more contacts, and a new listing with none cannot get its foot in the door
     * however good it is.
     *
     * Capped at 0.15, which is less than half the gap between a well-reviewed
     * crop and an unreviewed one. Contacts can therefore settle a near-tie and
     * nothing more: a heavily contacted crop with no reviews still loses to a
     * properly reviewed one.
     */
    protected const FEED_CONTACT_WEIGHT = 0.15;

    /**
     * Contact count at which the boost above is fully earned.
     *
     * The curve saturates here so the signal degrades gracefully: ten contacts
     * is most of the available credit, and the difference between a hundred and
     * a thousand contacts is close to nothing. Only relative position within
     * this range is meaningful, which is what a buyer perceives anyway.
     */
    protected const FEED_CONTACT_SATURATION = 8;

    /**
     * Blend of the three terms. Sums to 1.
     *
     * Popularity outweighs discovery because it is the more reliable signal,
     * and affinity outweighs both because it is the only one specific to this
     * request. Note what these weights CANNOT do: they tilt, they do not bound.
     * A user with strong history could still fill a whole page from one
     * category, which is why the discovery reserve below exists as a hard floor
     * rather than as another weight.
     */
    protected const FEED_WEIGHT_AFFINITY = 0.55;

    protected const FEED_WEIGHT_POPULARITY = 0.30;

    protected const FEED_WEIGHT_FRESHNESS = 0.15;

    /**
     * Days over which a new listing's freshness boost decays to nothing.
     *
     * Without this a listing's only chance is the moment it is posted, and the
     * feed has no way to distinguish "posted just now" from "posted last March
     * and still fine". A week is long enough that a seller who posts on Monday
     * is still being found on Sunday.
     */
    protected const FEED_FRESHNESS_DAYS = 7;

    /**
     * How many listings in a page are reserved for under-exposed listings.
     *
     * THE DISCOVERY FLOOR. Ranking alone does not guarantee fairness: with a
     * strong history, 0.55 of affinity is enough to fill an entire page from one
     * category, and the new and quiet listings then never appear at all — which
     * is the exact unfairness the ranking was meant to fix, reintroduced one
     * layer up. So this many slots per page are filled first from listings that
     * have had the least exposure (newest first, ties broken by fewest
     * contacts), and the ranked remainder fills what is left.
     *
     * Two of ten. Small enough that the feed still reads as personalised, large
     * enough that a seller posting their first crop is actually seen.
     */
    protected const FEED_DISCOVERY_SLOTS = 2;

    /**
     * Reads page/per_page, clamped rather than rejected.
     *
     * Clamping because a hand-typed per_page=9999 should get the maximum, not a
     * 422: this endpoint is public and unpaged browsing must never start
     * failing. Absent means the caller did not opt in, which the caller checks
     * before it decides to paginate at all.
     *
     * @return array{page: int|null, perPage: int|null}
     */
    protected function readFeedPaging(Request $request): array
    {
        $paged = $request->query('page') !== null
            || $request->query('per_page') !== null;

        if (! $paged) {
            return ['page' => null, 'perPage' => null];
        }

        $page = max(1, (int) $request->query('page', 1));
        $perPage = (int) $request->query('per_page', 10);

        // 30 is the ceiling, and 1 the floor: per_page=0 would make forPage()
        // return an empty page while claiming rows exist.
        return [
            'page' => $page,
            'perPage' => max(1, min(30, $perPage)),
        ];
    }

    /**
     * The category ids this user has searched for recently, most-wanted first.
     *
     * Derived by matching each recent keyword against category names, because
     * search_log stores the word the buyer typed ("tomato") and not a category
     * id. Matching on the name is what makes "tomato" resolve to the vegetable
     * category without a mapping table nobody maintains.
     *
     * Category-level only, not listing-level. Boosting the exact listings
     * someone searched for reads as surveillance and collapses the feed to a
     * single crop; boosting the category is the useful part and cannot do that.
     *
     * @return array<string, float> category id => affinity 0..1
     */
    protected function categoryAffinities(?object $user): array
    {
        if ($user === null) {
            return [];
        }

        $categories = CropCategory::all(['CAT_ID', 'CAT_NAME']);
        if ($categories->isEmpty()) {
            return [];
        }

        $knownIds = $categories->pluck('CAT_ID')->all();

        $searches = SearchLog::where('USR_ID', $user->USR_ID)
            // The recent window is what keeps this a nudge and not a profile.
            // A search from a year ago should not still be steering the feed.
            ->where('SRCH_CREATED_AT', '>=', now()->subDays(30))
            ->orderByDesc('SRCH_CREATED_AT')
            ->limit(50)
            ->get(['SRCH_KEYWORD', 'SRCH_FILTERS']);

        if ($searches->isEmpty()) {
            return [];
        }

        $hits = [];

        foreach ($searches as $search) {
            // The exact category comes first, when the search screen recorded one.
            // This is the reliable path: a tapped category filter carries its id,
            // so "Leafy Vegetables" needs no guesswork. Only ids that actually
            // exist are credited, otherwise a hand-typed filter would invent a
            // category that matches nothing.
            $filters = $search->SRCH_FILTERS
                ? json_decode((string) $search->SRCH_FILTERS, true)
                : null;

            $filteredCategory = is_array($filters) ? ($filters['category'] ?? null) : null;

            if ($filteredCategory !== null && in_array($filteredCategory, $knownIds, true)) {
                $hits[$filteredCategory] = ($hits[$filteredCategory] ?? 0) + 1;
                continue;
            }

            // Fallback for a typed keyword, which stores no category id. Matching
            // on the name is what lets "leafy vegetables" resolve to the vegetable
            // category without a mapping table nobody maintains. It cannot map
            // every word — "tomato" to "Vegetables" needs the category filter or a
            // curated synonym list — which is why this is the fallback and not
            // the only path.
            $keyword = mb_strtolower(trim((string) $search->SRCH_KEYWORD));
            if ($keyword === '') {
                continue;
            }

            foreach ($categories as $category) {
                $name = mb_strtolower($category->CAT_NAME);

                if ($name !== '' && str_contains($name, $keyword)) {
                    $hits[$category->CAT_ID] = ($hits[$category->CAT_ID] ?? 0) + 1;
                }
            }
        }

        if ($hits === []) {
            return [];
        }

        // Normalise to 0..1 against the strongest match, so the blend weight
        // means the same thing regardless of how chatty the search history is.
        $top = max($hits);

        return array_map(fn ($count) => $count / $top, $hits);
    }

    /**
     * The three ranking terms for one listing, each normalised to 0..1.
     *
     * @param  int  $ratingCount  visible reviews on this listing
     * @param  int  $contacts  contact log rows
     * @param  float|null  $ratingAverage  null when unrated
     * @param  float|null  $affinity  0..1 from the user's category history
     */
    protected function feedScore(
        Listing $listing,
        ?float $ratingAverage,
        int $ratingCount,
        int $contacts,
        ?float $affinity,
    ): float {
        // Bayesian average: pull the real average toward the prior, with a
        // weight of FEED_PRIOR_WEIGHT reviews. Unrated lands exactly on the
        // prior, which is the honest reading of "nobody has judged this yet".
        $quality = $ratingCount > 0
            ? (($ratingAverage ?? 0.0) * $ratingCount
                + self::FEED_PRIOR_MEAN * self::FEED_PRIOR_WEIGHT)
                / ($ratingCount + self::FEED_PRIOR_WEIGHT)
            : self::FEED_PRIOR_MEAN;

        // Normalised to 0..1 across the 1..5 scale before it touches the blend. The
        // contact term is added after, saturating at FEED_CONTACT_WEIGHT so it
        // can break a near-tie without ever overturning a real rating gap.
        $contactBoost = self::FEED_CONTACT_WEIGHT * min(
            1.0,
            log(1 + max(0, $contacts)) / log(1 + self::FEED_CONTACT_SATURATION)
        );

        $popularity = (($quality - 1.0) / 4.0) + $contactBoost;

        $ageInDays = $listing->LST_CREATED_AT
            ? max(0, now()->diffInDays($listing->LST_CREATED_AT, absolute: true))
            : self::FEED_FRESHNESS_DAYS;

        $freshness = 1.0 - min(1.0, $ageInDays / self::FEED_FRESHNESS_DAYS);

        $score = self::FEED_WEIGHT_POPULARITY * $popularity
            + self::FEED_WEIGHT_FRESHNESS * $freshness
            + self::FEED_WEIGHT_AFFINITY * ($affinity ?? 0.0);

        return $score;
    }

    /**
     * Orders, ranks and slices a feed query, returning [listings, lastPage, total].
     *
     * The candidate pool is bounded BEFORE ranking. Ranking an unbounded set in
     * PHP would reorder exactly what it had already downloaded and would fix
     * nothing, which is the trap this whole change exists to avoid: 120 rows
     * covers far more than any page needs, so nobody sees listing 121.
     *
     * $total is therefore the size of that pool, and $lastPage is derived from
     * it. Both describe the set the pages are actually cut from — reporting the
     * table's full matching count alongside a pool-derived last_page would give
     * the caller a page count it can never reach.
     *
     * @param  \Illuminate\Database\Eloquent\Builder  $query
     * @param  array<string, float>  $affinities
     * @return array{0: \Illuminate\Support\Collection, 1: int, 2: int}
     */
    protected function rankAndSliceFeed($query, array $affinities, ?int $page, ?int $perPage)
    {
        $poolSize = ($perPage ?? 10) * 12;

        // The pool is assembled from three bounded slices, not one. A single
        // newest-first slice would be simple, and it would be wrong: a crop
        // posted last month with fifty good reviews loses to a fresh one with
        // none, so the rating term would never get to act on exactly the
        // listings it exists to judge. One slice each for recency, contact
        // volume and review count means every signal has something to rank, and
        // the union is still capped, which is the property that matters.
        //
        // withCount folds each count in as a subquery, so every slice is one
        // round trip rather than one query per listing.
        $pooled = (clone $query)->withCount('contacts');
        $slice = max(1, intdiv($poolSize, 3));

        $recent = (clone $pooled)
            ->orderByDesc('LST_CREATED_AT')
            ->limit($slice)
            ->get();

        $busy = (clone $pooled)
            ->orderByDesc('contacts_count')
            ->orderByDesc('LST_CREATED_AT')
            ->limit($slice)
            ->get();

        $reviewed = (clone $pooled)
            ->withCount(['reviews as review_count' => fn ($q) => $q->visible()])
            ->orderByDesc('review_count')
            ->orderByDesc('LST_CREATED_AT')
            ->limit($slice)
            ->get();

        // A listing can land in more than one slice, and the merged set has to
        // be unique or the same card would be ranked, sliced and returned twice.
        $candidates = $recent
            ->concat($busy)
            ->concat($reviewed)
            ->unique('LST_ID')
            ->values();

        $total = $candidates->count();

        if ($page === null || $perPage === null) {
            return [$candidates, 1, $total];
        }

        $scored = $candidates
            ->map(function (Listing $listing) use ($affinities) {
                $listing->feed_score = $this->feedScore(
                    $listing,
                    $listing->rating_average === null ? null : (float) $listing->rating_average,
                    (int) ($listing->rating_count ?? 0),
                    (int) ($listing->contacts_count ?? 0),
                    $affinities[$listing->CAT_ID] ?? null,
                );

                return $listing;
            })
            // Ties broken by newest, then by id, so two refreshes of an unchanged
            // feed return the same order and pagination cannot drop or repeat a
            // row between pages.
            ->sortByDesc(fn (Listing $l) => [$l->feed_score, $l->LST_CREATED_AT, $l->LST_ID])
            ->values();

        // The discovery reserve. Reserved slots go to the listings that have had the
        // least exposure so far: fewest contacts, and among those the newest.
        // Ascending on contacts with a negated timestamp does both in one sort,
        // and taking the head means the genuinely untried rise. The obvious
        // mistake here is to reach for ->reverse() on a plain sortBy, which
        // flips both keys at once and reserves the MOST exposed listings instead
        // of the least — the exact opposite of the rule.
        //
        // strtotime rather than ->getTimestamp(): Listing does not cast
        // LST_CREATED_AT to a date, so the attribute is still a string here.
        $underExposed = $scored
            ->sortBy(fn (Listing $l) => [
                (int) ($l->contacts_count ?? 0),
                -(($l->LST_CREATED_AT ? strtotime((string) $l->LST_CREATED_AT) : 0)),
            ])
            ->take(self::FEED_DISCOVERY_SLOTS)
            ->keyBy('LST_ID');

        $offset = ($page - 1) * $perPage;
        $window = $scored->slice($offset, $perPage);

        // Only the first page injects the reserve: putting it on every page
        // would surface the same two new listings repeatedly as the user scrolls
        // and would crowd out the personalised results they scrolled for.
        if ($page === 1 && $underExposed->isNotEmpty()) {
            $window = $this->injectDiscoverySlots($window, $underExposed, $perPage);
        }

        $lastPage = max(1, (int) ceil($total / $perPage));

        return [$window->values(), $lastPage, $total];
    }

    /**
     * Swaps the tail of the first page for reserved discovery listings.
     *
     * @param  \Illuminate\Support\Collection  $window
     * @param  \Illuminate\Support\Collection  $underExposed
     * @return \Illuminate\Support\Collection
     */
    protected function injectDiscoverySlots($window, $underExposed, int $perPage)
    {
        $rows = $window->all();
        $reserved = $underExposed->reject(
            fn (Listing $l) => collect($rows)->contains('LST_ID', $l->LST_ID)
        )->take(self::FEED_DISCOVERY_SLOTS);

        if ($reserved->isEmpty()) {
            return $window;
        }

        // Replace from the end so the personalised head of the page is left
        // exactly as ranked.
        $slots = min($reserved->count(), $perPage);
        $offset = max(0, count($rows) - $slots);

        $merged = array_values($rows);
        array_splice($merged, $offset, $slots, $reserved->values()->all());

        return collect($merged);
    }
}