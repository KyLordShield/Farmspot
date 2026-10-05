<?php

namespace App\Http\Controllers;

use App\Models\ListingReview;
use Illuminate\Http\Request;

/**
 * Admin moderation for buyer reviews.
 *
 * Deliberately narrow: this page can hide a review and un-hide it again, and
 * that is all. There is no create, no edit and no hard delete, for two
 * reasons.
 *
 * First, a review is not the admin's text. Rewriting it would put words in a
 * buyer's mouth, and deleting it would destroy evidence of what was said about
 * a seller. Hiding is reversible and leaves the row intact.
 *
 * Second, hiding is what actually matters downstream. A HIDDEN review drops out
 * of the public list AND out of the listing's rating average, because both read
 * through the same visible() scope. One button therefore fixes the card and the
 * number together, with no recalculation step to forget.
 */
class ReviewController extends Controller
{
    public function index(Request $request)
    {
        $reviews = ListingReview::with(['user', 'listing.farm', 'listing.category'])
            ->when($request->filled('search'), function ($query) use ($request) {
                $term = $request->search;

                // Matches the reviewer, the crop, the farm or the review id.
                // whereHas on the relations keeps it to one query; a join would
                // risk fan-out duplicating review rows when a listing matched
                // the term through more than one path.
                $query->where(function ($q) use ($term) {
                    $q->where('LRV_ID', 'like', "%{$term}%")
                        ->orWhere('LRV_COMMENT', 'like', "%{$term}%")
                        ->orWhereHas('user', function ($uq) use ($term) {
                            $uq->where('USR_NAME', 'like', "%{$term}%");
                        })
                        ->orWhereHas('listing', function ($lq) use ($term) {
                            $lq->where('LST_ID', 'like', "%{$term}%")
                                ->orWhere('LST_CROP_ICON', 'like', "%{$term}%")
                                ->orWhereHas('farm', function ($fq) use ($term) {
                                    $fq->where('FRM_NAME', 'like', "%{$term}%");
                                })
                                ->orWhereHas('category', function ($cq) use ($term) {
                                    $cq->where('CAT_NAME', 'like', "%{$term}%");
                                });
                        });
                });
            })
            ->when(in_array($request->status, [ListingReview::STATUS_VISIBLE, ListingReview::STATUS_HIDDEN], true),
                fn ($q) => $q->where('LRV_STATUS', $request->status))
            ->when($request->filled('rating'), function ($query) use ($request) {
                $rating = (int) $request->rating;

                // Only 1..5 is reachable from the dropdown. Guarded rather than
                // passed through so a hand-typed ?rating=9 cannot match
                // nothing and look like a broken filter.
                if ($rating >= 1 && $rating <= 5) {
                    $query->where('LRV_RATING', $rating);
                }
            })
            // Newest first by time, not by LRV_ID: that column is six random
            // digits and sorting them compares them as strings.
            ->orderByDesc('LRV_CREATED_AT')
            ->orderByDesc('LRV_ID')
            ->paginate(15)
            ->withQueryString();

        // Counts are deliberately two cheap counts rather than an aggregate over
        // the paginated rows, so the two stat cards keep describing every
        // review in the table and not just the fifteen on this page.
        return view('reviews', [
            'reviews' => $reviews,
            'visibleCount' => ListingReview::visible()->count(),
            'hiddenCount' => ListingReview::hidden()->count(),
        ]);
    }

    /**
     * Flip a review between VISIBLE and HIDDEN.
     *
     * One PATCH for both directions rather than two buttons, so the action a
     * moderator takes cannot disagree with the state it was offered from: the
     * target state is derived from what the row is now.
     *
     * No audit_log write. Nothing in the admin panel writes there any more —
     * Report enforcement moved to report_action — so introducing a lone writer
     * for one feature would create a trail that only partly exists.
     */
    public function toggleStatus(Request $request, $id)
    {
        $review = ListingReview::find($id);

        if (! $review) {
            return redirect()->route('reviews')
                ->with('error', 'Review not found.');
        }

        if ($review->isHidden()) {
            $review->LRV_STATUS = ListingReview::STATUS_VISIBLE;
            $message = 'Review is visible again.';
        } else {
            $review->LRV_STATUS = ListingReview::STATUS_HIDDEN;
            $message = 'Review hidden from buyers. The listing average has been updated.';
        }

        $review->LRV_UPDATED_AT = now();
        $review->save();

        // The filter and search the moderator was looking at are preserved, so
        // hiding a row does not throw them back to page one of an unfiltered
        // list and lose their place in the queue.
        return redirect()
            ->route('reviews', array_filter($request->only(['search', 'status', 'rating', 'page'])))
            ->with('success', $message);
    }
}