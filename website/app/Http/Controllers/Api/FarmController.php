<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\FormatsListings;
use App\Http\Controllers\Controller;
use App\Models\ContactLog;
use App\Models\Farm;
use App\Models\FarmPhoto;
use App\Models\FarmVisitLog;
use App\Models\Listing;
use App\Models\Whitelist;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class FarmController extends Controller
{
    use FormatsListings;

    /**
     * Create a new farm for the authenticated seller candidate.
     *
     * Requires only that the user has a Farmer row (created by the "Become a
     * Seller" step) so they can submit a farm. Whitelist approval is decided
     * here, at submission time: whitelisted users get an instant-approve farm
     * (FRM_STATUS=APPROVED) and have their seller flags flipped, everyone else
     * gets FRM_STATUS=PENDING_REVIEW for admin review. The old
     * FMR_SELLER_MODE_ACTIVE gate is gone because that flag is now only set on
     * this approval path.
     */
    public function store(Request $request)
    {
        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer) {
            return response()->json([
                'message' => 'Start the seller setup first.',
            ], 403);
        }

        // One farm per farmer: an existing APPROVED or PENDING_REVIEW farm
        // blocks a new submission. Only when every prior farm is REJECTED
        // (e.g. after admin review) may the farmer submit again.
        $hasActiveFarm = $farmer->farms()
            ->whereIn('FRM_STATUS', ['APPROVED', 'PENDING_REVIEW'])
            ->exists();

        if ($hasActiveFarm) {
            return response()->json([
                'message' => 'You already have a farm. Each farmer can only have one farm at a time.',
            ], 409);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:150'],
            'description' => ['nullable', 'string'],
            'barangay' => ['required', 'string', 'max:100'],
            'latitude' => ['required', 'numeric'],
            'longitude' => ['required', 'numeric'],
            'photos' => ['required', 'array', 'min:1'],
            'photos.*' => ['image', 'max:5120'],
            'verification_document' => ['nullable', 'file', 'mimes:jpg,jpeg,png,pdf', 'max:5120'],
        ]);

        $isWhitelisted = Whitelist::where('WLST_MOBILE_NUMBER', $user->USR_MOBILE_NUMBER)
            ->where('WLST_IS_ACTIVE', 1)
            ->exists();

        $farmId = $this->uniqueId('farm', 'FRM_ID');

        try {
            $result = DB::transaction(function () use ($validated, $farmId, $farmer, $user, $isWhitelisted) {
                $verificationUrl = null;

                if (isset($validated['verification_document'])) {
                    $doc = $validated['verification_document'];
                    $extension = $doc->getClientOriginalExtension() ?: 'jpg';
                    $path = "farm-verification/{$farmId}/" . uniqid() . ".{$extension}";

                    Storage::disk('cloudinary')->put($path, $doc->getRealPath());

                    $verificationUrl = Storage::disk('cloudinary')->url($path);
                }

                $farm = Farm::create([
                    'FRM_ID' => $farmId,
                    'FRM_NAME' => $validated['name'],
                    'FRM_DESCRIPTION' => $validated['description'] ?? null,
                    'FRM_BARANGAY' => $validated['barangay'],
                    'FRM_LATITUDE' => $validated['latitude'],
                    'FRM_LONGITUDE' => $validated['longitude'],
                    'FRM_PIN_ACTIVE' => $isWhitelisted ? 1 : 0,
                    'FRM_STATUS' => $isWhitelisted ? 'APPROVED' : 'PENDING_REVIEW',
                    'FRM_CREATED_AT' => now(),
                    'FRM_VERIFICATION_DOC_PATH' => $verificationUrl,
                    'FMR_ID' => $farmer->FMR_ID,
                ]);

                if ($isWhitelisted) {
                    $farmer->FMR_SELLER_MODE_ACTIVE = 1;
                    $farmer->FMR_VERIFIED_AT = $farmer->FMR_VERIFIED_AT ?? now();
                    $farmer->save();

                    $user->USR_IS_SELLER = 1;
                    $user->save();
                }

                $urls = [];

                foreach ($validated['photos'] as $photo) {
                    $extension = $photo->getClientOriginalExtension() ?: 'jpg';
                    $path = "farm-photos/{$farmId}/" . uniqid() . ".{$extension}";

                    Storage::disk('cloudinary')->put($path, $photo->getRealPath());

                    $url = Storage::disk('cloudinary')->url($path);

                    FarmPhoto::create([
                        'FPHOTO_ID' => $this->uniqueId('farm_photo', 'FPHOTO_ID'),
                        'FPHOTO_FILE_PATH' => $url,
                        'FPHOTO_UPLOADED_AT' => now(),
                        'FRM_ID' => $farm->FRM_ID,
                    ]);

                    $urls[] = $url;
                }

                return [
                    'photo_urls' => $urls,
                    'verification_document_url' => $verificationUrl,
                ];
            });
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'Failed to create farm.',
            ], 500);
        }

        return response()->json([
            'message' => 'Farm created successfully.',
            'farm_id' => $farmId,
            'frm_status' => $isWhitelisted ? 'APPROVED' : 'PENDING_REVIEW',
            'photo_urls' => $result['photo_urls'],
            'verification_document_url' => $result['verification_document_url'],
        ], 201);
    }

    /**
     * Public farm map pins for the buyer-facing map screen.
     *
     * Requires no authentication (same public access level as the buyer feed).
     * Returns every farm that should be visible on the map — FRM_STATUS =
     * APPROVED and FRM_PIN_ACTIVE = 1 — in a compact shape for a map card:
     * coordinates, the farm's name/barangay, a count of currently
     * AVAILABLE_NOW + ACTIVE listings, and the first uploaded photo as a
     * thumbnail. Ordered newest-first, no pagination (pilot scale).
     */
    public function mapPins(Request $request)
    {
        $farms = Farm::with([
            'photos' => fn ($query) => $query->orderBy('FPHOTO_UPLOADED_AT'),
        ])
            ->withCount([
                'listings as active_listings_count' => function ($query) {
                    $query->where('LST_STATUS', 'AVAILABLE_NOW')
                        ->where('LST_AVAILABILITY', 'ACTIVE');
                },
            ])
            ->where('FRM_STATUS', 'APPROVED')
            ->where('FRM_PIN_ACTIVE', 1)
            ->orderByDesc('FRM_CREATED_AT')
            ->get();

        return response()->json([
            'farms' => $farms->map(fn ($farm) => [
                'id' => $farm->FRM_ID,
                'name' => $farm->FRM_NAME,
                'barangay' => $farm->FRM_BARANGAY,
                'latitude' => $farm->FRM_LATITUDE,
                'longitude' => $farm->FRM_LONGITUDE,
                'active_listings_count' => $farm->active_listings_count,
                'photo_url' => $farm->photos->first()?->FPHOTO_FILE_PATH,
            ]),
        ]);
    }

    /**
     * Public farm profile for the buyer-facing Farm Profile screen.
     *
     * Requires no authentication (same public access level as the buyer feed).
     * Returns the farm's details + photos plus ALL of its listings in the same
     * flat shape the seller listing endpoints use — any status/availability,
     * including NOT_AVAILABLE/REMOVED rows the buyer feed hides — ordered by
     * status priority (Available Now, then Soon to Harvest, then Not
     * Available) and, within each group, newest first.
     */
    public function profile(Request $request, $farmId)
    {
        $farm = Farm::with('photos')->find($farmId);

        if (! $farm) {
            return response()->json([
                'message' => 'Farm not found.',
            ], 404);
        }

        $listings = Listing::with(['category', 'farm', 'photos'])
            ->where('FRM_ID', $farm->FRM_ID)
            ->orderByRaw("FIELD(LST_STATUS, 'AVAILABLE_NOW', 'SOON_TO_HARVEST', 'NOT_AVAILABLE')")
            ->orderByDesc('LST_CREATED_AT')
            ->get()
            ->map(fn ($listing) => $this->formatListing($listing));

        return response()->json([
            'farm' => $this->formatFarm($farm),
            'listings' => $listings,
        ]);
    }

    /**
     * Edit the authenticated seller's own farm (auth + ownership required).
     *
     * JSON-only: name and description. Location is locked after approval — a
     * request that tries to send latitude/longitude/barangay is rejected with
     * a validation error. FRM_STATUS is never touched — editing an approved
     * farm doesn't send it back to review.
     *
     * NOTE: photo uploads CANNOT ride this PATCH — PHP only populates
     * $_FILES (and $_POST) for POST requests, so a multipart PATCH arrives
     * with empty input/files on this stack. Photos go through
     * POST /api/farms/{id}/photos instead.
     */
    public function update(Request $request, $farmId)
    {
        $farm = Farm::with('photos')->find($farmId);

        if (! $farm) {
            return response()->json([
                'message' => 'Farm not found.',
            ], 404);
        }

        $farmer = $request->user()->buyer?->farmer;

        if (! $farmer || $farm->FMR_ID !== $farmer->FMR_ID) {
            return response()->json([
                'message' => 'You do not own this farm.',
            ], 403);
        }

        $validated = $request->validate([
            'name' => ['nullable', 'string', 'max:150'],
            'description' => ['nullable', 'string'],
            // Location is locked after approval — reject any attempt to change it.
            // ("prohibited" passes only when the field is absent or empty, so an
            // edit form that always sends blank coord fields still works.)
            'latitude' => ['prohibited'],
            'longitude' => ['prohibited'],
            'barangay' => ['prohibited'],
        ], [
            'latitude.prohibited' => 'Location cannot be changed after the farm is approved.',
            'longitude.prohibited' => 'Location cannot be changed after the farm is approved.',
            'barangay.prohibited' => 'Location cannot be changed after the farm is approved.',
        ]);

        if (array_key_exists('name', $validated)) {
            $farm->FRM_NAME = $validated['name'];
        }

        if (array_key_exists('description', $validated)) {
            $farm->FRM_DESCRIPTION = $validated['description'];
        }

        $farm->save();

        return response()->json([
            'message' => 'Farm updated successfully.',
            'farm' => $this->formatFarm(Farm::with('photos')->find($farm->FRM_ID)),
        ]);
    }

    /**
     * Append new photos to the authenticated seller's own farm (POST so the
     * multipart uploads are actually parsed by PHP). New uploads go to
     * Cloudinary exactly like POST /api/farms and are APPENDED as new
     * farm_photo rows — the existing set is never replaced or deleted.
     */
    public function addPhotos(Request $request, $farmId)
    {
        $farm = Farm::with('photos')->find($farmId);

        if (! $farm) {
            return response()->json([
                'message' => 'Farm not found.',
            ], 404);
        }

        $farmer = $request->user()->buyer?->farmer;

        if (! $farmer || $farm->FMR_ID !== $farmer->FMR_ID) {
            return response()->json([
                'message' => 'You do not own this farm.',
            ], 403);
        }

        $validated = $request->validate([
            'photos' => ['required', 'array', 'min:1'],
            'photos.*' => ['image', 'max:5120'],
        ]);

        foreach ($validated['photos'] as $photo) {
            $extension = $photo->getClientOriginalExtension() ?: 'jpg';
            $path = "farm-photos/{$farm->FRM_ID}/" . uniqid() . ".{$extension}";

            Storage::disk('cloudinary')->put($path, $photo->getRealPath());

            FarmPhoto::create([
                'FPHOTO_ID' => $this->uniqueId('farm_photo', 'FPHOTO_ID'),
                'FPHOTO_FILE_PATH' => Storage::disk('cloudinary')->url($path),
                'FPHOTO_UPLOADED_AT' => now(),
                'FRM_ID' => $farm->FRM_ID,
            ]);
        }

        return response()->json([
            'message' => 'Farm photos added successfully.',
            'farm' => $this->formatFarm(Farm::with('photos')->find($farm->FRM_ID)),
        ]);
    }

    /**
     * Log a single farm-profile visit for the authenticated user.
     * Every open inserts one row — no deduplication of repeat visits.
     */
    public function logVisit(Request $request, $farmId)
    {
        $farm = Farm::find($farmId);

        if (! $farm) {
            return response()->json([
                'message' => 'Farm not found.',
            ], 404);
        }

        do {
            $visitId = strtoupper(Str::random(6));
        } while (FarmVisitLog::where('FVL_ID', $visitId)->exists());

        FarmVisitLog::create([
            'FVL_ID' => $visitId,
            'USR_ID' => $request->user()->USR_ID,
            'FRM_ID' => $farm->FRM_ID,
            'FVL_CREATED_AT' => now(),
        ]);

        return response()->json([
            'message' => 'Farm visit logged.',
            'visit_id' => $visitId,
            'farm_id' => $farm->FRM_ID,
        ], 201);
    }

    /**
     * Performance stats for the authenticated seller's own farm (auth-only,
     * ownership required — 403 when the caller doesn't own the farm).
     *
     * Flipped from the buyer perspective to the farm-owner perspective:
     *   - profile_views: real farm_visit_log rows whose FRM_ID is this farm
     *     (every time anyone opens this farm's profile, logged by logVisit)
     *   - buyer_contacts: real contact_log rows whose LST_ID is one of THIS
     *     farm's listings (buyers who actually tapped Call/SMS on the farm)
     *   - active_listings: listings on this farm that are both
     *     LST_STATUS='AVAILABLE_NOW' and LST_AVAILABILITY='ACTIVE'
     */
    public function stats(Request $request, $farmId)
    {
        $farm = Farm::find($farmId);

        if (! $farm) {
            return response()->json([
                'message' => 'Farm not found.',
            ], 404);
        }

        $farmer = $request->user()->buyer?->farmer;

        if (! $farmer || $farm->FMR_ID !== $farmer->FMR_ID) {
            return response()->json([
                'message' => 'You do not own this farm.',
            ], 403);
        }

        $listingIds = Listing::where('FRM_ID', $farm->FRM_ID)->pluck('LST_ID');

        return response()->json([
            'profile_views' => FarmVisitLog::where('FRM_ID', $farm->FRM_ID)->count(),
            'buyer_contacts' => ContactLog::whereIn('LST_ID', $listingIds)->count(),
            'active_listings' => Listing::where('FRM_ID', $farm->FRM_ID)
                ->where('LST_STATUS', 'AVAILABLE_NOW')
                ->where('LST_AVAILABILITY', 'ACTIVE')
                ->count(),
        ]);
    }

    /**
     * List the authenticated seller's own operational farms.
     * Returns an empty list for users who have no farm yet
     * (e.g. seller mode active but wizard never completed).
     *
     * REJECTED farms are historical/inert and deliberately omitted — the app
     * treats this list as "my farm(s)" and shows it selectable when creating
     * listings, so only APPROVED / PENDING_REVIEW belong here. A farmer whose
     * only farm was rejected therefore sees an empty list and may re-submit.
     *
     * Ordered deterministically so clients can rely on the first entry being
     * "the" farm: APPROVED first, then PENDING_REVIEW, newest-created within
     * each status. APPROVED on top matches the client's "one active farm"
     * convention (APPROVED is the only operational one).
     */
    public function index(Request $request)
    {
        $user = $request->user();

        $farms = $user->buyer?->farmer?->farms()
            ->whereIn('FRM_STATUS', ['APPROVED', 'PENDING_REVIEW'])
            ->orderByRaw("FIELD(FRM_STATUS, 'APPROVED', 'PENDING_REVIEW')")
            ->orderByDesc('FRM_CREATED_AT')
            ->get() ?? collect();

        return response()->json([
            'farms' => $farms,
        ]);
    }

    /**
     * Shape a Farm model into the structured farm object the public profile
     * and the farm-edit endpoints share (id, name, description, barangay,
     * coordinates, status, photos).
     */
    private function formatFarm(Farm $farm): array
    {
        return [
            'id' => $farm->FRM_ID,
            'name' => $farm->FRM_NAME,
            'description' => $farm->FRM_DESCRIPTION,
            'barangay' => $farm->FRM_BARANGAY,
            'latitude' => $farm->FRM_LATITUDE,
            'longitude' => $farm->FRM_LONGITUDE,
            'status' => $farm->FRM_STATUS,
            'photos' => $farm->photos->pluck('FPHOTO_FILE_PATH'),
        ];
    }

    private function uniqueId($table, $column): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }
}