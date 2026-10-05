<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\ListingReview;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Buyer reviews on a listing: a 1-5 star rating plus an optional comment.
 *
 * The reviewer is always the bearer token, never the request body, and the
 * three rules that matter are the same shape as ReportController's:
 *
 *   1. You cannot review your own listing.
 *   2. A REMOVED listing cannot be reviewed. It is off sale, so a rating for
 *      it would outlive the thing being rated.
 *   3. One review per user per listing. The UNIQUE key on (LST_ID, USR_ID) is
 *      what guarantees it; store() turns the second submission into an update
 *      instead of an error, because changing your mind is normal.
 *
 * Privacy note: the reviewer is shown as first name + last initial ("Juan D.")
 * and nothing else. USR_EMAIL and USR_MOBILE_NUMBER are never in this payload.
 */
class ListingReviewController extends Controller
{
    /** Newest first, and what an absent or unusable ?sort falls back to. */
    public const SORT_NEWEST = 'newest';

    /** Rating, then has a comment, then newest. The product detail preview. */
    public const SORT_BEST = 'best';

    /** Rating alone, highest first, ignoring whether a comment was left. */
    public const SORT_HIGHEST = 'highest';

    /** Rating alone, lowest first. */
    public const SORT_LOWEST = 'lowest';

    /** Every accepted ?sort value. Membership is checked with in_array. */
    public const SORTS = [
        self::SORT_NEWEST,
        self::SORT_BEST,
        self::SORT_HIGHEST,
        self::SORT_LOWEST,
    ];

    /**
     * Paginated visible reviews for a listing, plus the summary.
     *
     * Public like the buyer feed it sits on, because reviews are shown on a
     * public listing page. When a bearer token happens to be present the
     * caller's own review rides along in `my_review`, which is what lets the
     * rate sheet open already filled in; guests get null and see the plain
     * "write a review" state.
     *
     * Three optional query parameters narrow or reorder the list. All are
     * additive: with none of them present the response is byte-for-byte what it
     * was before, apart from the new `rating_breakdown` inside `summary`.
     *
     *   ?rating=1..5     only that many stars
     *   ?with_comment=   true only reviews with words, false only bare ratings
     *   ?sort=           newest (default), best, highest, lowest
     *
     * `summary` is always computed over every visible review, never over the
     * filtered set, so the header average and the chip counts cannot change
     * because of a filter the buyer chose.
     *
     * `my_review` is likewise unaffected by the filters, so a buyer who has
     * reviewed this listing can always find and edit their own row even when the
     * active filter would have excluded it.
     */
    public function index(Request $request, $listingId)
    {
        $listing = Listing::find($listingId);

        if (! $listing) {
            return response()->json(['message' => 'Listing not found.'], 404);
        }

        $perPage = $this->perPage($request);

        // Both are optional and both default to the pre-existing behaviour:
        // newest first, unfiltered. An unusable value is dropped rather than
        // rejected, so a stale or hand-edited client keeps the list it had
        // before instead of getting an error page.
        $rating = $this->ratingFilter($request);
        $withComment = $this->withCommentFilter($request);
        $sort = $this->sort($request);

        $query = ListingReview::with('user')
            ->where('LST_ID', $listing->LST_ID)
            ->visible()
            // Applied before any ordering, and always inside visible() so a
            // hidden review cannot be narrowed down to by guessing a rating.
            ->when($rating !== null, fn (Builder $q) => $q->where('LRV_RATING', $rating))
            ->when($withComment === true, fn (Builder $q) => $q->whereNotNull('LRV_COMMENT'))
            ->when($withComment === false, fn (Builder $q) => $q->whereNull('LRV_COMMENT'));

        $this->applySort($query, $sort);

        $reviews = $query->paginate($perPage);

        // Deliberately NOT built from $query: the average, the count and the
        // breakdown describe every visible review of the listing, so the header
        // cannot shift when a buyer filters down to "5 stars" or opens a later
        // page. A filtered list showing an average of only what survived the
        // filter is how a 3.9 listing ends up advertising itself as a 5.0.
        $totals = ListingReview::where('LST_ID', $listing->LST_ID)
            ->visible()
            ->selectRaw('COUNT(*) as total, AVG(LRV_RATING) as average')
            ->first();

        // One extra grouped query rather than five, and independent of the
        // filters above on purpose, matching the totals.
        $breakdown = ListingReview::where('LST_ID', $listing->LST_ID)
            ->visible()
            ->selectRaw('LRV_RATING as rating, COUNT(*) as total')
            ->groupBy('LRV_RATING')
            ->pluck('total', 'rating');

        $user = $request->user('sanctum');

        $mine = $user
            ? ListingReview::with('user')
                ->where('LST_ID', $listing->LST_ID)
                ->where('USR_ID', $user->USR_ID)
                ->first()
            : null;

        // Resolved once and reused for both fields: canReview() walks the
        // farmer -> buyer -> user chain, and calling it twice would run that
        // query twice to fill two fields of one response.
        $blocked = $this->canReview($user, $listing);

        return response()->json([
            'reviews' => collect($reviews->items())
                ->map(fn (ListingReview $review) => $this->format($review, $user))
                ->values(),
            'summary' => [
                // null, not 0.0: an unreviewed listing is not a zero-star one,
                // and the app renders nothing at all when this is null.
                //
                // Rounded here rather than in SQL so the number the app sees is
                // exactly what the visible review list supports.
                'average' => $totals->average === null
                    ? null
                    : round((float) $totals->average, 1),
                'count' => (int) $totals->total,
                // New field, additive: counts per rating over every VISIBLE
                // review, unaffected by ?rating and ?with_comment. All five keys
                // are always present so the app never has to guard a missing
                // index to decide whether to print "(8)" beside a chip.
                //
                // The keys are strings because JSON object keys are, and they
                // are built rather than cast so a rating with no reviews reads
                // as 0 instead of vanishing and shifting the chip order.
                'rating_breakdown' => $this->breakdown($breakdown),
            ],
            'my_review' => $mine ? $this->format($mine, $user) : null,
            'can_review' => $blocked === null,
            'review_blocked_reason' => $blocked,
            'current_page' => $reviews->currentPage(),
            'last_page' => $reviews->lastPage(),
            'per_page' => $reviews->perPage(),
            'total' => $reviews->total(),
        ]);
    }

    /**
     * Create the caller's review, or update the one they already left.
     *
     * 201 when a review is created, 200 when an existing one was overwritten,
     * so the app can tell "thanks, posted" from "we replaced your old one"
     * without a second request. The response carries the review and a fresh
     * summary so the header the buyer is looking at updates in the same
     * response that saved the review.
     */
    public function store(Request $request, $listingId)
    {
        $listing = Listing::find($listingId);

        if (! $listing) {
            return response()->json(['message' => 'Listing not found.'], 404);
        }

        $user = $request->user();

        $blocked = $this->canReview($user, $listing);
        if ($blocked !== null) {
            return response()->json(['message' => $blocked], 403);
        }

        $validated = $request->validate([
            'rating' => ['required', 'integer', 'min:1', 'max:5'],
            'comment' => ['nullable', 'string', 'max:300'],
        ], [
            'rating.required' => 'Please pick a star rating.',
            'rating.min' => 'Please pick between 1 and 5 stars.',
            'rating.max' => 'Please pick between 1 and 5 stars.',
            'comment.max' => 'Keep your review under 300 characters.',
        ]);

        // Trimmed, and a comment that is only whitespace becomes null rather
        // than an empty row that renders as a blank bubble. 'nullable' alone
        // admits "   ", which is not the same as saying nothing.
        $comment = isset($validated['comment']) && trim($validated['comment']) !== ''
            ? trim($validated['comment'])
            : null;

        $existing = ListingReview::where('LST_ID', $listing->LST_ID)
            ->where('USR_ID', $user->USR_ID)
            ->first();

        if ($existing) {
            $existing->LRV_RATING = (int) $validated['rating'];
            $existing->LRV_COMMENT = $comment;
            $existing->LRV_UPDATED_AT = now();
            $existing->save();

            $review = $existing;
            $status = 200;
            $message = 'Your review was updated.';
        } else {
            $review = ListingReview::create([
                'LRV_ID' => ListingReview::newId(),
                'LST_ID' => $listing->LST_ID,
                'USR_ID' => $user->USR_ID,
                'LRV_RATING' => (int) $validated['rating'],
                'LRV_COMMENT' => $comment,
                'LRV_STATUS' => ListingReview::STATUS_VISIBLE,
                'LRV_CREATED_AT' => now(),
                'LRV_UPDATED_AT' => now(),
            ]);

            $status = 201;
            $message = 'Thanks for your review.';
        }

        // Read back so LRV_STATUS and the timestamps are the stored values
        // rather than whatever we just asked for.
        $review->refresh();
        $review->load('user');

        return response()->json([
            'message' => $message,
            'review' => $this->format($review, $user),
            'summary' => $this->summaryFor($listing->LST_ID),
        ], $status);
    }

    /**
     * Delete the caller's own review.
     *
     * Scoped to the owner by the query rather than fetched-then-checked, so
     * someone else's review id is indistinguishable from one that never
     * existed — a 404 rather than a 403 that would confirm it does.
     *
     * Unlike an admin hide, this is a real delete: it is the reviewer's own
     * words about their own experience, and they are entitled to withdraw
     * them. The listing's other reviews and the FK cascade on the listing
     * itself are unaffected.
     */
    public function destroy(Request $request, $listingId)
    {
        $listing = Listing::find($listingId);

        if (! $listing) {
            return response()->json(['message' => 'Listing not found.'], 404);
        }

        $user = $request->user();

        $review = ListingReview::where('LST_ID', $listing->LST_ID)
            ->where('USR_ID', $user->USR_ID)
            ->first();

        if (! $review) {
            return response()->json(['message' => 'Review not found.'], 404);
        }

        $review->delete();

        return response()->json([
            'message' => 'Your review was deleted.',
            'summary' => $this->summaryFor($listing->LST_ID),
        ]);
    }

    /**
     * Why this person may not review this listing right now, or null if they can.
     *
     * Returns the message rather than a bare boolean so the app has one string
     * to show, and so the same sentence is used by the endpoint that refuses
     * the write and by the `can_review` hint on the read. An inactive account
     * is included here rather than in a middleware, because GET is public and
     * has to report the same state without demanding a token.
     */
    private function canReview(?User $user, Listing $listing): ?string
    {
        if (! $user) {
            return 'Sign in to write a review.';
        }

        if ($user->USR_STATUS !== 'ACTIVE') {
            return 'Your account must be active to write a review.';
        }

        if ($listing->LST_AVAILABILITY === Listing::AVAILABILITY_REMOVED) {
            return 'This listing is no longer available to review.';
        }

        if ($this->farmerOwnerId($listing->FMR_ID) === $user->USR_ID) {
            return 'This is your own listing.';
        }

        return null;
    }

    /**
     * The user id behind a farmer record, or null if the chain is unlinked.
     *
     * Same joined lookup ReportController uses for its own-listing guard: a
     * farmer hangs off a buyer, not off a user directly, so the walk is
     * buyer -> user. Written as one query because it runs on every review read.
     */
    private function farmerOwnerId(?string $farmerId): ?string
    {
        if (! $farmerId) {
            return null;
        }

        return Farmer::join('buyer', 'buyer.BUY_ID', '=', 'farmer.BUY_ID')
            ->where('farmer.FMR_ID', $farmerId)
            ->value('buyer.USR_ID');
    }

    /**
     * The {average, count} block for a listing, visible reviews only.
     *
     * Shared with store() and destroy() so the summary they return cannot drift
     * from the one index() sends. The breakdown rides along there too: a buyer
     * who writes or deletes a review and closes the sheet expects the chip
     * counts to move with the average, not a request later.
     */
    private function summaryFor(string $listingId): array
    {
        $summary = ListingReview::where('LST_ID', $listingId)
            ->visible()
            ->selectRaw('COUNT(*) as total, AVG(LRV_RATING) as average')
            ->first();

        $breakdown = ListingReview::where('LST_ID', $listingId)
            ->visible()
            ->selectRaw('LRV_RATING as rating, COUNT(*) as total')
            ->groupBy('LRV_RATING')
            ->pluck('total', 'rating');

        return [
            'average' => $summary->average === null
                ? null
                : round((float) $summary->average, 1),
            'count' => (int) $summary->total,
            'rating_breakdown' => $this->breakdown($breakdown),
        ];
    }

    /**
     * Counts for ratings 1 to 5, every key always present.
     *
     * A rating nobody chose reads as 0 rather than being left out: the app
     * renders the chips in descending order from these, so a missing key would
     * mean a guard on every read and a blank gap in the row.
     *
     * @param  \Illuminate\Support\Collection<int, mixed>  $counts  rating => total
     */
    private function breakdown($counts): array
    {
        $breakdown = [];

        for ($rating = 1; $rating <= 5; $rating++) {
            $breakdown[(string) $rating] = (int) ($counts[$rating] ?? 0);
        }

        return $breakdown;
    }

    /**
     * The requested star filter, or null to leave every rating in.
     *
     * Anything outside 1..5 is ignored rather than rejected. ?rating=9 from a
     * stale client is a bug on that side, and failing the request would blank
     * the whole reviews list over a parameter the server can simply not honour.
     */
    private function ratingFilter(Request $request): ?int
    {
        $raw = $request->query('rating');

        if ($raw === null || $raw === '') {
            return null;
        }

        // "3abc" must not become 3: is_numeric first, then the range.
        if (! is_numeric($raw)) {
            return null;
        }

        $rating = (int) $raw;

        return $rating >= 1 && $rating <= 5 ? $rating : null;
    }

    /**
     * The requested comment filter: true, false, or null for "don't care".
     *
     * True admits only reviews with words. False admits only bare star ratings,
     * which is why this is tri-state rather than a bool — a missing parameter
     * has to mean "both", not "only stars".
     *
     * Accepts true/false/1/0/yes/no. Anything else is ignored.
     */
    private function withCommentFilter(Request $request): ?bool
    {
        $raw = $request->query('with_comment');

        if ($raw === null || $raw === '') {
            return null;
        }

        $value = is_bool($raw) ? $raw : strtolower((string) $raw);

        if (in_array($value, ['1', 'true', 'yes'], true)) {
            return true;
        }

        if (in_array($value, ['0', 'false', 'no'], true)) {
            return false;
        }

        return null;
    }

    /**
     * Which ordering to use, defaulting to newest first.
     *
     * An unrecognised value falls back to the default rather than erroring, for
     * the same reason the rating filter does.
     *
     * in_array, not array_key_exists: SORTS is a list of values rather than a
     * map of value => true, so a key lookup would answer "no" for every input
     * including "best", and quietly serve newest-first to a buyer who asked for
     * the best reviews.
     */
    private function sort(Request $request): string
    {
        $sort = strtolower(trim((string) $request->query('sort', self::SORT_NEWEST)));

        return in_array($sort, self::SORTS, true) ? $sort : self::SORT_NEWEST;
    }

    /**
     * Order the visible-and-filtered query.
     *
     * Every branch ends in the same id tiebreak. LRV_ID is six random digits, so
     * without it two reviews sharing a rating and a second would come back in a
     * different order on each request, and a buyer paging through "Best" would
     * see rows swap places between pages.
     */
    private function applySort(Builder $query, string $sort): void
    {
        switch ($sort) {
            case self::SORT_BEST:
                // Best is what the product detail preview uses for its top three,
                // so the order has to be defensible: rating first, then reviews
                // that bothered to write something, then newest. A 5-star "Great"
                // outranks a 5-star tap, which in turn outranks an older 5.
                $query->orderByDesc('LRV_RATING')
                    ->orderByRaw('CASE WHEN LRV_COMMENT IS NULL THEN 1 ELSE 0 END')
                    ->orderByDesc('LRV_CREATED_AT');
                break;

            case self::SORT_HIGHEST:
                $query->orderByDesc('LRV_RATING')->orderByDesc('LRV_CREATED_AT');
                break;

            case self::SORT_LOWEST:
                $query->orderBy('LRV_RATING')->orderByDesc('LRV_CREATED_AT');
                break;

            default:
                $query->orderByDesc('LRV_CREATED_AT');
                break;
        }

        $query->orderByDesc('LRV_ID');
    }

    /**
     * Page size, clamped so ?per_page= cannot be used to ask for the whole
     * table in one response.
     */
    private function perPage(Request $request): int
    {
        $perPage = (int) $request->query('per_page', 5);

        return max(1, min($perPage, 50));
    }

    /**
     * One review as the app receives it.
     *
     * `is_mine` is resolved against the caller rather than trusted from the
     * row, so a client can style its own review without a second request.
     *
     * `reviewer` comes from the model's reviewerName(), which is also what the
     * admin table renders, so the public API and the moderation screen cannot
     * end up abbreviating names differently.
     */
    private function format(ListingReview $review, ?User $viewer): array
    {
        return [
            'id' => $review->LRV_ID,
            'listing_id' => $review->LST_ID,
            'rating' => (int) $review->LRV_RATING,
            'comment' => $review->LRV_COMMENT,
            'reviewer' => $review->reviewerName(),
            'created_at' => $review->LRV_CREATED_AT,
            'updated_at' => $review->LRV_UPDATED_AT,
            'is_mine' => $viewer !== null && $viewer->USR_ID === $review->USR_ID,
        ];
    }
}