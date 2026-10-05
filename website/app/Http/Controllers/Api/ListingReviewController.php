<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\ListingReview;
use App\Models\User;
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
    /**
     * Paginated visible reviews for a listing, plus the summary.
     *
     * Public like the buyer feed it sits on, because reviews are shown on a
     * public listing page. When a bearer token happens to be present the
     * caller's own review rides along in `my_review`, which is what lets the
     * rate sheet open already filled in; guests get null and see the plain
     * "write a review" state.
     */
    public function index(Request $request, $listingId)
    {
        $listing = Listing::find($listingId);

        if (! $listing) {
            return response()->json(['message' => 'Listing not found.'], 404);
        }

        $perPage = $this->perPage($request);

        $reviews = ListingReview::with('user')
            ->where('LST_ID', $listing->LST_ID)
            ->visible()
            // Newest first. By time rather than by id: LRV_ID is six random
            // digits, so sorting those would compare them as strings and hand
            // back an arbitrary order.
            ->orderByDesc('LRV_CREATED_AT')
            ->orderByDesc('LRV_ID')
            ->paginate($perPage);

        // One aggregate over the visible rows only, matching exactly what the
        // list above shows. A hidden review is out of both at once, so the
        // average can never disagree with the reviews the buyer can read.
        $summary = ListingReview::where('LST_ID', $listing->LST_ID)
            ->visible()
            ->selectRaw('COUNT(*) as total, AVG(LRV_RATING) as average')
            ->first();

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
                'average' => $summary->average === null
                    ? null
                    : round((float) $summary->average, 1),
                'count' => (int) $summary->total,
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
     */
    private function summaryFor(string $listingId): array
    {
        $summary = ListingReview::where('LST_ID', $listingId)
            ->visible()
            ->selectRaw('COUNT(*) as total, AVG(LRV_RATING) as average')
            ->first();

        return [
            'average' => $summary->average === null
                ? null
                : round((float) $summary->average, 1),
            'count' => (int) $summary->total,
        ];
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
     */
    private function format(ListingReview $review, ?User $viewer): array
    {
        return [
            'id' => $review->LRV_ID,
            'listing_id' => $review->LST_ID,
            'rating' => (int) $review->LRV_RATING,
            'comment' => $review->LRV_COMMENT,
            'reviewer' => $this->displayName($review->user?->USR_NAME),
            'created_at' => $review->LRV_CREATED_AT,
            'updated_at' => $review->LRV_UPDATED_AT,
            'is_mine' => $viewer !== null && $viewer->USR_ID === $review->USR_ID,
        ];
    }

    /**
     * "Juan D." from "Juan Dela Cruz" — first name plus last initial.
     *
     * RA 10173: a review is public, so it must not carry an email address or a
     * mobile number. The full registered name is trimmed to this shape rather
     * than truncated by length, so the middle name never survives.
     *
     * A one-word name has no initial to take and is returned as-is. A missing
     * name falls back to a neutral label instead of an empty string, so a
     * review is never rendered with a blank byline.
     */
    private function displayName(?string $fullName): string
    {
        $parts = preg_split('/\s+/', trim((string) $fullName), -1, PREG_SPLIT_NO_EMPTY);

        if (! $parts) {
            return 'A buyer';
        }

        if (count($parts) === 1) {
            return $parts[0];
        }

        return $parts[0] . ' ' . mb_substr($parts[count($parts) - 1], 0, 1) . '.';
    }
}