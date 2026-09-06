<?php

namespace App\Http\Controllers\Api;

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

        $listings = Listing::with(['category', 'farm'])
            ->where('FRM_ID', $farm->FRM_ID)
            ->orderByRaw("FIELD(LST_STATUS, 'AVAILABLE_NOW', 'SOON_TO_HARVEST', 'NOT_AVAILABLE')")
            ->orderByDesc('LST_CREATED_AT')
            ->get()
            ->map(fn ($listing) => $this->formatListing($listing));

        return response()->json([
            'farm' => [
                'id' => $farm->FRM_ID,
                'name' => $farm->FRM_NAME,
                'description' => $farm->FRM_DESCRIPTION,
                'barangay' => $farm->FRM_BARANGAY,
                'latitude' => $farm->FRM_LATITUDE,
                'longitude' => $farm->FRM_LONGITUDE,
                'status' => $farm->FRM_STATUS,
                'photos' => $farm->photos->pluck('FPHOTO_FILE_PATH'),
            ],
            'listings' => $listings,
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
     * List the authenticated seller's own farms.
     * Returns an empty list for users who have no farm yet
     * (e.g. seller mode active but wizard never completed).
     */
    public function index(Request $request)
    {
        $user = $request->user();

        $farms = $user->buyer?->farmer?->farms ?? collect();

        return response()->json([
            'farms' => $farms,
        ]);
    }

    /**
     * Shape a Listing model into the same flat JSON structure the seller
     * listing endpoints use (id, crop_icon, status, availability,
     * harvest_date, expiry_date, image, category, farm), so the Farm Profile
     * screen shares a consistent contract with the rest of the app.
     */
    private function formatListing(Listing $listing): array
    {
        return [
            'id' => $listing->LST_ID,
            'crop_icon' => $listing->LST_CROP_ICON,
            'status' => $listing->LST_STATUS,
            'availability' => $listing->LST_AVAILABILITY,
            'harvest_date' => $listing->LST_HARVEST_DATE,
            'expiry_date' => $listing->LST_EXPIRY_DATE,
            'image' => $listing->LST_IMAGE,
            'created_at' => $listing->LST_CREATED_AT,
            'category' => [
                'id' => $listing->category->CAT_ID ?? null,
                'name' => $listing->category->CAT_NAME ?? null,
                'icon' => $listing->category->CAT_ICON ?? null,
            ],
            'farm' => [
                'id' => $listing->farm->FRM_ID ?? null,
                'name' => $listing->farm->FRM_NAME ?? null,
                'barangay' => $listing->farm->FRM_BARANGAY ?? null,
            ],
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