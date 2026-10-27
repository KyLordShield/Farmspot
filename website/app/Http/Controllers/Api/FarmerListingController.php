<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\FormatsListings;
use App\Http\Controllers\Controller;
use App\Models\Farm;
use App\Models\Listing;
use App\Models\ListingPhoto;
use App\Models\ListingReview;
use App\Models\Report;
use App\Models\ReviewRequest;
use App\Services\CropCategorySuggestion;
use App\Support\CloudinaryImage;
use App\Support\InputLimits;
use App\Support\ListingName;
use App\Support\PhotoLimits;
use Closure;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class FarmerListingController extends Controller
{
    use FormatsListings;

    /**
     * List the authenticated farmer's own listings, any LST_STATUS /
     * LST_AVAILABILITY (unlike the buyer-facing feed which is active-only).
     * Includes the farm and category relations.
     *
     * REMOVED is excluded by default, and it is the whole point of that default
     * after moderation: an admin-removed listing is not the farmer's to edit, so
     * keeping it in the default response only offers a dead row that fails on
     * every action. ?include_removed=1 turns it back on, because the My Farm
     * screen does need to SHOW it — a seller whose crop was taken down has to be
     * able to see that, with the reason, and cannot do anything about it.
     *
     * Four optional parameters, all additive. A caller that sends none of them
     * gets the previous response, unchanged in shape and content:
     *
     *   ?farm_id=FRM123  only one farm's listings. Without it every farm is
     *                    returned, which is what the multi-farm screen did by
     *                    filtering client-side — a filter that cannot survive
     *                    paging, since a page of "all farms" is not a page of
     *                    "this farm".
     *   ?page=1          1-based. Only sent by a paged caller.
     *   ?per_page=10     1..30, default 10, clamped rather than rejected.
     *   ?status=         all (default) | active | expired | hidden | under_review
     *
     * Paging is opt-in rather than always-on for the same reason: an unpaged
     * response is not a one-page response, and pretending otherwise would make
     * this endpoint quietly mean two different things depending on the caller.
     * The app sends page + per_page; everything else keeps the old list.
     *
     * Two new response fields ride along either way. `pagination` is present
     * only on a paged response, and `summary` always carries the totals and the
     * review aggregate a paged list cannot count for itself — counting loaded
     * rows would report "10 listings" for a seller with forty.
     */
    /**
     * The listing columns this endpoint returns, named explicitly so a paged
     * list of thirty rows does not also drag every unused column of a table
     * that carries descriptions and photo caches. formatListing() reads only
     * these, plus the subqueries added after this call.
     */
    private const LIST_COLUMNS = [
        'LST_ID',
        'LST_CROP_ICON',
        'LST_STATUS',
        'LST_AVAILABILITY',
        'LST_HARVEST_DATE',
        'LST_EXPIRY_DATE',
        'LST_LAST_RENEWED_AT',
        'LST_RENEWAL_COUNT',
        'LST_DESCRIPTION',
        'LST_IMAGE',
        'LST_TAKEDOWN_REASON',
        'LST_TAKEDOWN_AT',
        'LST_CREATED_AT',
        'LST_UPDATED_AT',
        'FMR_ID',
        'FRM_ID',
        'CAT_ID',
    ];

    /** What an admin sets a listing to when buyers must not see it at all. */
    private const ADMIN_HIDDEN = [Listing::AVAILABILITY_REMOVED, 'NOT_AVAILABLE'];

    /** Every accepted ?status value. An absent one falls back to "all". */
    private const STATUS_FILTERS = ['all', 'active', 'expired', 'hidden', 'under_review'];

    /** Rows per page when a paged caller does not ask for a size. */
    private const DEFAULT_PER_PAGE = 10;

    /**
     * The ceiling on ?per_page. Thirty rows is already more than a phone screen
     * will hold, so anything larger is a mistake rather than a wish.
     */
    private const MAX_PER_PAGE = 30;

    public function myListings(Request $request)
    {
        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer) {
            return response()->json([
                'message' => 'No farmer account found.',
            ], 403);
        }

        $farmId = $this->farmIdFilter($request);
        $status = $this->statusFilter($request);

        // Built by the same two steps whether or not the caller asked for
        // paging, so a filtered response and an unfiltered one are the same
        // query with a different WHERE. Building the filter twice is how a
        // "hidden by admin" chip ends up counting something the list below it
        // does not show.
        $scope = fn () => Listing::where('FMR_ID', $farmer->FMR_ID)
            ->when($farmId !== null, fn ($q) => $q->where('FRM_ID', $farmId))
            ->when(! $this->wantsRemoved($request), fn ($q) => $q->where('LST_AVAILABILITY', '!=', Listing::AVAILABILITY_REMOVED));

        // has_open_report is a correlated EXISTS folded into the listing query,
        // not an eager load of the reports: thirty rows must not become thirty
        // extra queries, and nothing about the report itself is ever selected —
        // only the fact that an open one exists. The seller's row says
        // "Under review" and stops there.
        $openReport = Report::query()
            ->selectRaw('1')
            ->whereColumn('report.LST_ID', 'listing.LST_ID')
            ->whereIn('report.RPT_STATUS', Report::OPEN_STATUSES)
            ->limit(1);

        $query = $scope()
            ->with(['farm', 'category', 'photos'])
            // Read-only rating summary for the seller's own My Farm view. Same
            // subquery aggregate as the buyer-facing endpoints, so a seller sees
            // exactly the number a buyer does. Added AFTER select() so the
            // aggregate subqueries append to it instead of replacing it.
            ->select(self::LIST_COLUMNS)
            ->addSelect([
                'has_pending_appeal' => ReviewRequest::selectRaw('1')
                    ->where('RRQ_TARGET_TYPE', ReviewRequest::TARGET_LISTING)
                    ->whereColumn('RRQ_TARGET_ID', 'listing.LST_ID')
                    ->where('RRQ_STATUS', 'PENDING')
                    ->limit(1),
            ])
            ->withRatingSummary()
            ->withExists(['reports as has_open_report' => fn ($q) => $q->whereIn('RPT_STATUS', Report::OPEN_STATUSES)]);

        $this->applyStatusFilter($query, $status);

        // Three sort keys, because paging cannot repeat a result. Two listings
        // created in the same second tie on LST_CREATED_AT, and page 2 would
        // then start from wherever the database felt like: the same row twice,
        // or one row never.
        $ordered = $query
            ->orderByDesc('LST_CREATED_AT')
            ->orderByDesc('LST_UPDATED_AT')
            ->orderByDesc('LST_ID');

        $paged = $this->wantsPaging($request);

        if ($paged) {
            $page = max(1, (int) $request->query('page', 1));
            $perPage = $this->perPage($request);
            $rows = $ordered->paginate($perPage, ['*'], 'page', $page);
            $listings = $rows->getCollection()->map(fn ($listing) => $this->formatListing($listing));
        } else {
            $listings = $ordered->get()->map(fn ($listing) => $this->formatListing($listing));
        }

        $response = [
            'listings' => $listings,
            'summary' => $this->myListingsSummary($farmer->FMR_ID, $farmId, $scope),
        ];

        if ($paged) {
            $response['pagination'] = [
                'current_page' => $rows->currentPage(),
                'last_page' => max(1, $rows->lastPage()),
                'total' => $rows->total(),
                'per_page' => $rows->perPage(),
            ];
        }

        return response()->json($response);
    }

    /**
     * Totals for the whole scope — never for the page, and never for the
     * active filter.
     *
     * A seller's own numbers have to survive paging: a filter chip reading
     * "Expired 1" while the list below it is page 2 of Active is worse than no
     * chip at all, and that is exactly what counting loaded rows produces. It
     * is also why this is computed before the ?status filter is applied.
     *
     * Four counts come out of one conditional-aggregation query, and the
     * farm-wide rating average out of a second. That second one is AVG over
     * every visible review row, not an average of the per-listing averages: the
     * two disagree as soon as one listing has 90 reviews and another has 2, and
     * only the first is the number a buyer would compute.
     */
    private function myListingsSummary(string $farmerId, ?string $farmId, Closure $scope): array
    {
        $openReport = Report::query()
            ->selectRaw('1')
            ->whereColumn('report.LST_ID', 'listing.LST_ID')
            ->whereIn('report.RPT_STATUS', Report::OPEN_STATUSES)
            ->limit(1);

        $counts = $scope()
            ->selectRaw(
                'COUNT(*) as total_count,
                 SUM(CASE WHEN listing.LST_STATUS != \'SOON_TO_HARVEST\' AND listing.LST_EXPIRY_DATE < NOW() THEN 1 ELSE 0 END) as expired_count,
                 SUM(CASE WHEN listing.LST_AVAILABILITY IN (?, ?) THEN 1 ELSE 0 END) as hidden_count,
                 SUM(CASE WHEN EXISTS('.$openReport->toSql().') THEN 1 ELSE 0 END) as under_review_count',
                array_merge(self::ADMIN_HIDDEN, $openReport->getBindings())
            )
            ->first();

        $total = (int) ($counts->total_count ?? 0);
        $expired = (int) ($counts->expired_count ?? 0);
        $hidden = (int) ($counts->hidden_count ?? 0);
        $underReview = (int) ($counts->under_review_count ?? 0);

        $reviews = ListingReview::query()
            ->join('listing', 'listing.LST_ID', '=', 'listing_review.LST_ID')
            ->where('listing.FMR_ID', $farmerId)
            ->when($farmId !== null, fn ($q) => $q->where('listing.FRM_ID', $farmId))
            // Same moderation rule as every rating number: a hidden review is
            // out of the average here exactly as it is out of the listing's own.
            ->where('listing_review.LRV_STATUS', 'VISIBLE')
            ->selectRaw('COUNT(*) as review_count, AVG(listing_review.LRV_RATING) as review_average')
            ->first();

        return [
            'total_listings' => $total,
            // The chips partition the scope, so the four numbers add up to the
            // total: a listing that is both expired and reported is counted as
            // expired, because that is the fact a seller has to act on first.
            'active_count' => max(0, $total - $expired - $hidden - $underReview),
            'expired_count' => $expired,
            'hidden_count' => $hidden,
            'under_review_count' => $underReview,
            'review_count' => (int) ($reviews->review_count ?? 0),
            // null rather than 0.0 for the same reason the per-listing average is
            // null: an unreviewed farm is not a zero-star one.
            'rating_average' => $reviews->review_average === null
                ? null
                : round((float) $reviews->review_average, 1),
        ];
    }

    /**
     * Restricts the list to one ?status bucket. "active" is the complement of
     * the other three rather than a fifth independent test, which is what keeps
     * the chip counts and the filtered list describing the same partition.
     */
    private function applyStatusFilter(Builder $query, string $status): void
    {
        $openReport = Report::query()
            ->selectRaw('1')
            ->whereColumn('report.LST_ID', 'listing.LST_ID')
            ->whereIn('report.RPT_STATUS', Report::OPEN_STATUSES)
            ->limit(1);

        match ($status) {
            'expired' => $query
                ->where('listing.LST_STATUS', '!=', 'SOON_TO_HARVEST')
                ->where('listing.LST_EXPIRY_DATE', '<', now()),
            'hidden' => $query->whereIn('listing.LST_AVAILABILITY', self::ADMIN_HIDDEN),
            'under_review' => $query->whereExists($openReport),
            'active' => $query
                ->where(function (Builder $q) {
                    // Soon to harvest is active regardless of the creation-time
                    // expiry: its three-day window starts at harvest, not when
                    // the crop was posted.
                    $q->where('listing.LST_STATUS', 'SOON_TO_HARVEST')
                        ->orWhere('listing.LST_EXPIRY_DATE', '>=', now());
                })
                ->whereNotIn('listing.LST_AVAILABILITY', self::ADMIN_HIDDEN)
                ->whereNotExists($openReport),
            default => null,
        };
    }

    /**
     * Whether this caller wants pages at all.
     *
     * Presence, not truthiness: page=0 is still a caller asking for paging, and
     * treating it as "no paging" would hand it every row instead of clamping
     * page 0 to page 1 like every other bad value.
     */
    private function wantsPaging(Request $request): bool
    {
        return $request->query->has('page') || $request->query->has('per_page');
    }

    /** 1..30. Unusable input becomes the default, never an error page. */
    private function perPage(Request $request): int
    {
        $raw = $request->query('per_page');

        if ($raw === null || ! is_numeric($raw)) {
            return self::DEFAULT_PER_PAGE;
        }

        return (int) max(1, min((int) $raw, self::MAX_PER_PAGE));
    }

    /** ?status, validated by membership rather than rejected. */
    private function statusFilter(Request $request): string
    {
        $status = (string) $request->query('status', 'all');

        return in_array($status, self::STATUS_FILTERS, true) ? $status : 'all';
    }

    /** ?farm_id, when it is present and non-empty. */
    private function farmIdFilter(Request $request): ?string
    {
        $farmId = $request->query('farm_id');
        $farmId = is_string($farmId) ? trim($farmId) : '';

        return $farmId === '' ? null : $farmId;
    }

    /**
     * ?include_removed=1 brings back admin-taken-down listings for the seller.
     * Anything else (absent, 0, off, nonsense) keeps the default exclusion, so
     * no existing caller can start receiving rows it never had.
     */
    private function wantsRemoved(Request $request): bool
    {
        return in_array((string) $request->query('include_removed', ''), ['1', 'true', 'yes'], true);
    }

    /**
     * The one instruction every path that cannot silently renew a listing
     * returns. Kept together so the app shows the same sentence whether the
     * seller used the status toggle, the edit form, or an old build's Renew
     * button.
     */
    private const RENEW_REQUIRED_MESSAGE =
        'This listing has expired. Renew it with a fresh photo to show it again.';

    /**
     * Update just the LST_STATUS of one of the farmer's own listings.
     *
     * A status change is not a renewal. It used to reset LST_EXPIRY_DATE on
     * every call, which meant re-sending the current status (the old app's
     * "Renew") or simply changing Not Available back to Available extended a
     * stale listing without any new evidence. Expiry now moves only when the
     * crop is created or explicitly renewed through renew().
     */
    public function updateStatus(Request $request, $listingId)
    {
        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer) {
            return response()->json([
                'message' => 'No farmer account found.',
            ], 403);
        }

        $listing = Listing::with(['farm', 'category', 'photos'])
            ->where('LST_ID', $listingId)
            ->where('FMR_ID', $farmer->FMR_ID)
            ->first();

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found or does not belong to you.',
            ], 403);
        }

        if ($removed = $this->removedListingGuard($listing)) {
            return $removed;
        }

        $validated = $request->validate([
            'status' => ['required', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
        ]);

        // The old client's Renew call sends the status the listing already has.
        // Returning a clear error is better than a 200 that pretends the expiry
        // moved while leaving the listing just as stale as it was.
        if ($validated['status'] === $listing->LST_STATUS) {
            if ($this->listingHasExpired($listing)) {
                return response()->json([
                    'message' => self::RENEW_REQUIRED_MESSAGE,
                ], 422);
            }

            return response()->json([
                'message' => 'Listing status is unchanged.',
                'listing' => $this->formatListing($listing),
            ]);
        }

        // Bringing an expired listing back on sale is a renewal, not an edit.
        // The dedicated endpoint is the only path allowed to extend it.
        if ($this->listingHasExpired($listing) && $validated['status'] !== 'NOT_AVAILABLE') {
            return response()->json([
                'message' => self::RENEW_REQUIRED_MESSAGE,
            ], 422);
        }

        $listing->LST_STATUS = $validated['status'];
        $listing->LST_UPDATED_AT = now();
        $listing->save();

        return response()->json([
            'message' => 'Listing status updated successfully.',
            'listing' => $this->formatListing($listing),
        ]);
    }

    /**
     * Full edit of one of the farmer's own listings — the general-purpose
     * counterpart to updateStatus() (which stays as the quick status toggle).
     *
     * JSON-only: any combination of category_id, crop_icon, harvest_date,
     * status. LST_EXPIRY_DATE is NEVER reset here. An edit — including a
     * corrected description or a new photo — must not silently buy another
     * three days; that is what renew() is for.
     *
     * NOTE: photo uploads CANNOT ride this PATCH — PHP only populates
     * $_FILES (and $_POST) for POST requests, so a multipart PATCH arrives
     * with empty input/files on this stack. Photo changes go through
     * POST /api/listings/{id}/photos (gallery) or the legacy
     * POST /api/listings/{id}/photo (single replace) instead.
     */
    public function update(Request $request, $listingId)
    {
        $listing = Listing::with(['farm', 'category', 'photos'])->find($listingId);

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found.',
            ], 404);
        }

        $farmer = $request->user()->buyer?->farmer;

        if (! $farmer || $listing->FMR_ID !== $farmer->FMR_ID) {
            return response()->json([
                'message' => 'You do not own this listing.',
            ], 403);
        }

        if ($removed = $this->removedListingGuard($listing)) {
            return $removed;
        }

        $validated = $request->validate([
            'category_id' => ['nullable', 'string', 'exists:crop_category,CAT_ID'],
            'crop_icon' => ['nullable', 'string', 'max:'.InputLimits::CROP_NAME],
            'description' => ['nullable', 'string', 'max:'.InputLimits::DESCRIPTION],
            'harvest_date' => ['nullable', 'date', 'required_if:status,SOON_TO_HARVEST'],
            'status' => ['nullable', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
        ], InputLimits::messages());

        if (! isset($validated['category_id']) && ! empty($validated['crop_icon'])) {
            $validated['category_id'] = app(CropCategorySuggestion::class)->assign($validated['crop_icon']);
        }

        return DB::transaction(function () use ($listing, $validated) {
            Farm::where('FRM_ID', $listing->FRM_ID)->lockForUpdate()->firstOrFail();
            if (array_key_exists('crop_icon', $validated)) {
                ListingName::ensureUnique($listing->FRM_ID, $validated['crop_icon'], $listing->LST_ID);
            }

            if (array_key_exists('category_id', $validated)) {
                $listing->CAT_ID = $validated['category_id'];
            }

            if (array_key_exists('crop_icon', $validated)) {
                $listing->LST_CROP_ICON = $validated['crop_icon'];
            }

            if (array_key_exists('description', $validated)) {
                $listing->LST_DESCRIPTION = $validated['description'];
            }

            if (array_key_exists('harvest_date', $validated)) {
                $listing->LST_HARVEST_DATE = $validated['harvest_date'];
            }

            if (array_key_exists('status', $validated)) {
                // Moving an expired listing back into an on-sale state is a
                // renewal. Editing text, category, or photos on the expired row is
                // still allowed; only the revival goes through renew().
                if (
                    $validated['status'] !== $listing->LST_STATUS
                    && $validated['status'] !== 'NOT_AVAILABLE'
                    && $this->listingHasExpired($listing)
                ) {
                    return response()->json([
                        'message' => self::RENEW_REQUIRED_MESSAGE,
                    ], 422);
                }

                $listing->LST_STATUS = $validated['status'];
            }

            $listing->LST_UPDATED_AT = now();
            $listing->save();

            $fresh = Listing::with(['farm', 'category', 'photos'])->find($listing->LST_ID);

            return response()->json([
                'message' => 'Listing updated successfully.',
                'listing' => $this->formatListing($fresh),
            ]);
        });
    }

    /**
     * Renew an expired listing with a fresh gallery of camera photos.
     *
     * This is deliberately separate from updateStatus() and update(): an
     * expiry extension is a claim that the crop is still available, so it
     * needs fresh images and its own audit fields. The request is multipart
     * because PHP does not populate files on PATCH.
     *
     * The renewal REPLACES the whole gallery, not just the primary photo. Old
     * secondary photos are last week's crop; leaving them next to a fresh
     * primary would mix old and new produce in one listing and make the
     * freshness claim misleading. `primary_index` picks which new photo is the
     * thumbnail, defaulting to the first.
     *
     * Only an expired listing can be renewed. A live listing already has its
     * window; allowing early renewal would let a seller extend forever without
     * ever waiting for the old window to end. SOON_TO_HARVEST is not expired:
     * its window starts when listings:harvest makes it available.
     */
    public function renew(Request $request, $listingId)
    {
        $farmer = $request->user()->buyer?->farmer;

        if (! $farmer) {
            return response()->json([
                'message' => 'No farmer account found.',
            ], 403);
        }

        $listing = Listing::with(['farm', 'category', 'photos'])
            ->where('LST_ID', $listingId)
            ->where('FMR_ID', $farmer->FMR_ID)
            ->first();

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found or does not belong to you.',
            ], 403);
        }

        if ($removed = $this->removedListingGuard($listing)) {
            return $removed;
        }

        if (! $this->listingHasExpired($listing)) {
            return response()->json([
                'message' => 'This listing is still active. Renew it after it expires.',
            ], 422);
        }

        $validated = $request->validate([
            // New clients send a photos[] gallery; the legacy single `photo`
            // field is still accepted so an older APK can renew after an
            // upgrade. At least one image is required either way.
            'photos' => ['nullable', 'array', 'min:1', 'max:'.PhotoLimits::LISTING],
            'photos.*' => ['image', 'max:5120'],
            'photo' => ['nullable', 'image', 'max:5120'],
            'primary_index' => ['nullable', 'integer', 'min:0'],
            'status' => ['required', 'in:AVAILABLE_NOW,SOON_TO_HARVEST'],
            'harvest_date' => ['nullable', 'date', 'after_or_equal:today', 'required_if:status,SOON_TO_HARVEST'],
        ]);

        $uploads = $validated['photos'] ?? [];
        if ($uploads === [] && isset($validated['photo'])) {
            $uploads = [$validated['photo']];
        }

        if ($uploads === []) {
            throw ValidationException::withMessages([
                'photos' => ['At least one fresh photo is required.'],
            ]);
        }

        $primaryIndex = max(
            0,
            min((int) ($validated['primary_index'] ?? 0), count($uploads) - 1)
        );

        $newUrls = [];

        try {
            foreach ($uploads as $index => $photo) {
                $extension = $photo->getClientOriginalExtension() ?: 'jpg';
                $path = "listing-photos/{$listing->LST_ID}/"
                    .uniqid()."-{$index}.{$extension}";

                Storage::disk('cloudinary')->put($path, $photo->getRealPath());
                $newUrls[] = Storage::disk('cloudinary')->url($path);
            }
        } catch (\Throwable $e) {
            foreach ($newUrls as $url) {
                CloudinaryImage::deleteByUrl($url);
            }

            return response()->json([
                'message' => 'Failed to upload the renewal photos.',
            ], 500);
        }

        // Every photo belongs to the previous renewal's crop evidence, so all
        // of it is replaced. Keeping the old secondary gallery images alongside
        // a fresh primary would show buyers last week's produce in the same
        // listing and make the freshness claim meaningless.
        $oldUrls = ListingPhoto::where('LST_ID', $listing->LST_ID)
            ->pluck('LPHOTO_FILE_PATH')
            ->filter()
            ->values()
            ->all();

        if ($listing->LST_IMAGE && ! in_array($listing->LST_IMAGE, $oldUrls, true)) {
            $oldUrls[] = $listing->LST_IMAGE;
        }

        try {
            DB::transaction(function () use ($listing, $validated, $newUrls, $primaryIndex) {
                Listing::whereKey($listing->LST_ID)->lockForUpdate()->firstOrFail();
                ListingPhoto::where('LST_ID', $listing->LST_ID)->delete();

                foreach ($newUrls as $index => $url) {
                    ListingPhoto::create([
                        'LPHOTO_ID' => $this->uniqueId('listing_photo', 'LPHOTO_ID'),
                        'LPHOTO_FILE_PATH' => $url,
                        'LPHOTO_UPLOADED_AT' => now(),
                        'LPHOTO_IS_PRIMARY' => $index === $primaryIndex ? 1 : 0,
                        'LST_ID' => $listing->LST_ID,
                    ]);
                }

                $listing->LST_IMAGE = $newUrls[$primaryIndex];
                $listing->LST_STATUS = $validated['status'];
                $listing->LST_HARVEST_DATE = $validated['status'] === 'SOON_TO_HARVEST'
                    ? $validated['harvest_date']
                    : null;
                $listing->LST_EXPIRY_DATE = now()->addDays(3);
                $listing->LST_LAST_RENEWED_AT = now();
                $listing->LST_RENEWAL_COUNT = ((int) $listing->LST_RENEWAL_COUNT) + 1;
                $listing->LST_UPDATED_AT = now();
                $listing->save();
            });
        } catch (\Throwable $e) {
            // The images were uploaded before the transaction so a failed upload
            // never leaves a half-written listing. If the database write fails,
            // remove those orphans instead of charging Cloudinary for them
            // forever.
            foreach ($newUrls as $url) {
                CloudinaryImage::deleteByUrl($url);
            }

            return response()->json([
                'message' => 'Failed to renew listing.',
            ], 500);
        }

        // Destroy the replaced gallery only after the new rows and listing are
        // committed, matching uploadPhoto(): a failed renewal must not lose the
        // old photos while the listing still points at them.
        foreach ($oldUrls as $oldUrl) {
            if (! in_array($oldUrl, $newUrls, true)) {
                CloudinaryImage::deleteByUrl($oldUrl);
            }
        }

        $fresh = Listing::with(['farm', 'category', 'photos'])->find($listing->LST_ID);

        return response()->json([
            'message' => 'Listing renewed for another 3 days.',
            'listing' => $this->formatListing($fresh),
        ]);
    }

    /**
     * LEGACY single-photo replace, kept working for the Flutter build that
     * still calls POST /api/listings/{id}/photo. Now gallery-aware: the new
     * image is appended as the listing's primary listing_photo row, every
     * other row is demoted, and the previous primary row + cloud asset are
     * removed. Non-primary gallery photos are left untouched. New clients
     * should use POST /api/listings/{id}/photos instead.
     */
    public function uploadPhoto(Request $request, $listingId)
    {
        $listing = Listing::with(['farm', 'category', 'photos'])->find($listingId);

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found.',
            ], 404);
        }

        $farmer = $request->user()->buyer?->farmer;

        if (! $farmer || $listing->FMR_ID !== $farmer->FMR_ID) {
            return response()->json([
                'message' => 'You do not own this listing.',
            ], 403);
        }

        if ($removed = $this->removedListingGuard($listing)) {
            return $removed;
        }

        $request->validate([
            'photo' => ['required', 'image', 'max:5120'],
        ]);

        [$newUrl, $oldImage] = DB::transaction(function () use ($request, $listing) {
            $listing = Listing::whereKey($listing->LST_ID)->lockForUpdate()->firstOrFail();
            $previousPrimary = ListingPhoto::where('LST_ID', $listing->LST_ID)->where('LPHOTO_IS_PRIMARY', 1)->first();
            $count = ListingPhoto::where('LST_ID', $listing->LST_ID)->count();
            PhotoLimits::ensure($count - ($previousPrimary ? 1 : 0), 1, PhotoLimits::LISTING, 'listing');
            $oldImage = $previousPrimary?->LPHOTO_FILE_PATH ?? $listing->LST_IMAGE;
            $photo = $request->file('photo');
            $extension = $photo->getClientOriginalExtension() ?: 'jpg';
            $path = "listing-photos/{$listing->LST_ID}/".uniqid().".{$extension}";
            Storage::disk('cloudinary')->put($path, $photo->getRealPath());
            $newUrl = Storage::disk('cloudinary')->url($path);
            ListingPhoto::where('LST_ID', $listing->LST_ID)->update(['LPHOTO_IS_PRIMARY' => 0]);
            ListingPhoto::create([
                'LPHOTO_ID' => $this->uniqueId('listing_photo', 'LPHOTO_ID'),
                'LPHOTO_FILE_PATH' => $newUrl,
                'LPHOTO_UPLOADED_AT' => now(), 'LPHOTO_IS_PRIMARY' => 1, 'LST_ID' => $listing->LST_ID,
            ]);
            $listing->LST_IMAGE = $newUrl;
            $listing->LST_UPDATED_AT = now();
            $listing->save();
            $previousPrimary?->delete();

            return [$newUrl, $oldImage];
        });

        // Destroy the old asset only AFTER the new one was uploaded and the row
        // has switched over, so a failed upload never loses the listing photo.
        if ($oldImage !== $newUrl) {
            CloudinaryImage::deleteByUrl($oldImage);
        }

        $fresh = Listing::with(['farm', 'category', 'photos'])->find($listing->LST_ID);

        return response()->json([
            'message' => 'Listing photo updated successfully.',
            'listing' => $this->formatListing($fresh),
        ]);
    }

    /**
     * Hard-delete one of the farmer's own listings (auth + ownership required).
     * Also destroys every Cloudinary gallery asset (primary and any additional
     * listing_photo rows) before the DB row goes away, so no cloud asset is
     * orphaned. The listing_photo rows themselves cascade-delete with the
     * listing FK.
     */
    public function destroy(Request $request, $listingId)
    {
        $listing = Listing::with('photos')->find($listingId);

        if (! $listing) {
            return response()->json([
                'message' => 'Listing not found.',
            ], 404);
        }

        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer || $listing->FMR_ID !== $farmer->FMR_ID) {
            return response()->json([
                'message' => 'You do not own this listing.',
            ], 403);
        }

        if ($removed = $this->removedListingGuard($listing)) {
            return $removed;
        }

        if ($listing->photos->isNotEmpty()) {
            foreach ($listing->photos as $photo) {
                CloudinaryImage::deleteByUrl($photo->LPHOTO_FILE_PATH);
            }
        } else {
            CloudinaryImage::deleteByUrl($listing->LST_IMAGE);
        }

        $listing->delete();

        return response()->json([
            'message' => 'Listing deleted successfully.',
            'deleted_id' => $listing->LST_ID,
        ]);
    }

    /**
     * Refuse to act on a listing a moderator removed. Returns null when the
     * listing is still the farmer's to edit, or the ready-to-return 403 when it
     * is not.
     *
     * 403 rather than 404 on purpose: the farmer already knows this listing
     * exists, and a 404 would send them hunting for a bug. Every call site runs
     * this AFTER the ownership check, so the guard can never be used to probe
     * whether somebody else's removed listing exists.
     */
    private function removedListingGuard(Listing $listing)
    {
        if (! $listing->isRemoved()) {
            return null;
        }

        return response()->json([
            'message' => Listing::REMOVED_EDIT_MESSAGE,
        ], 403);
    }

    /**
     * Whether the listing's three-day on-sale window has ended.
     *
     * A null expiry is treated as expired: legacy rows that never had one
     * cannot be "still active", and allowing them through renew() is safer than
     * leaving the seller with no way to refresh them.
     *
     * SOON_TO_HARVEST is never expired. It is not on sale yet, so the expiry
     * stamped at creation does not describe a window that has ended; the crop
     * stays "soon" until listings:harvest starts its window. Without this,
     * a crop harvested next week was treated as expired after three days.
     */
    private function listingHasExpired(Listing $listing): bool
    {
        if ($listing->LST_STATUS === 'SOON_TO_HARVEST') {
            return false;
        }

        return $listing->LST_EXPIRY_DATE === null
            || now()->greaterThanOrEqualTo($listing->LST_EXPIRY_DATE);
    }

    private function uniqueId($table, $column): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }
}
