<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\FormatsListings;
use App\Http\Controllers\Controller;
use App\Models\Listing;
use App\Models\ListingPhoto;
use App\Models\ListingReview;
use App\Models\Report;
use App\Support\CloudinaryImage;
use Closure;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

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
        'LST_DESCRIPTION',
        'LST_IMAGE',
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
                 SUM(CASE WHEN listing.LST_EXPIRY_DATE < NOW() THEN 1 ELSE 0 END) as expired_count,
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
            'expired' => $query->where('listing.LST_EXPIRY_DATE', '<', now()),
            'hidden' => $query->whereIn('listing.LST_AVAILABILITY', self::ADMIN_HIDDEN),
            'under_review' => $query->whereExists($openReport),
            'active' => $query
                ->where('listing.LST_EXPIRY_DATE', '>=', now())
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
     * Update just the LST_STATUS of one of the farmer's own listings.
     * Resets LST_EXPIRY_DATE to now()+3 days (expiry resets on any update),
     * per the capstone's rule.
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

        $listing->LST_STATUS = $validated['status'];
        $listing->LST_EXPIRY_DATE = now()->addDays(3);
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
     * status. LST_EXPIRY_DATE is NOT reset on a plain edit — only when status
     * is among the changed fields, matching updateStatus()'s expiry-reset
     * behavior.
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
            'crop_icon' => ['nullable', 'string'],
            'description' => ['nullable', 'string'],
            'harvest_date' => ['nullable', 'date'],
            'status' => ['nullable', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
        ]);

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
            $listing->LST_STATUS = $validated['status'];
            // Expiry resets whenever status changes, exactly like updateStatus().
            $listing->LST_EXPIRY_DATE = now()->addDays(3);
        }

        $listing->LST_UPDATED_AT = now();
        $listing->save();

        $fresh = Listing::with(['farm', 'category', 'photos'])->find($listing->LST_ID);

        return response()->json([
            'message' => 'Listing updated successfully.',
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

        $photo = $request->file('photo');
        $extension = $photo->getClientOriginalExtension() ?: 'jpg';
        $path = "listing-photos/{$listing->LST_ID}/" . uniqid() . ".{$extension}";

        Storage::disk('cloudinary')->put($path, $photo->getRealPath());
        $newUrl = Storage::disk('cloudinary')->url($path);

        // Capture the outgoing primary (or the plain LST_IMAGE for an
        // un-backfilled legacy row) before it is replaced.
        $previousPrimary = ListingPhoto::where('LST_ID', $listing->LST_ID)
            ->where('LPHOTO_IS_PRIMARY', 1)
            ->first();
        $oldImage = $previousPrimary?->LPHOTO_FILE_PATH ?? $listing->LST_IMAGE;

        DB::transaction(function () use ($listing, $newUrl, $previousPrimary) {
            ListingPhoto::where('LST_ID', $listing->LST_ID)
                ->update(['LPHOTO_IS_PRIMARY' => 0]);

            ListingPhoto::create([
                'LPHOTO_ID' => $this->uniqueId('listing_photo', 'LPHOTO_ID'),
                'LPHOTO_FILE_PATH' => $newUrl,
                'LPHOTO_UPLOADED_AT' => now(),
                'LPHOTO_IS_PRIMARY' => 1,
                'LST_ID' => $listing->LST_ID,
            ]);

            $listing->LST_IMAGE = $newUrl;
            $listing->LST_UPDATED_AT = now();
            $listing->save();

            $previousPrimary?->delete();
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

    private function uniqueId($table, $column): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }
}
