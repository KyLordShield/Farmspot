<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Api\Concerns\FormatsListings;
use App\Http\Controllers\Controller;
use App\Models\Listing;
use App\Models\ListingPhoto;
use App\Support\CloudinaryImage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class FarmerListingController extends Controller
{
    use FormatsListings;

    /**
     * List ALL listings belonging to the authenticated farmer — any
     * LST_STATUS / LST_AVAILABILITY (unlike the buyer-facing feed which is
     * active-only). Includes the farm and category relations.
     */
    public function myListings(Request $request)
    {
        $user = $request->user();

        $farmer = $user->buyer?->farmer;

        if (! $farmer) {
            return response()->json([
                'message' => 'No farmer account found.',
            ], 403);
        }

        $listings = Listing::with(['farm', 'category', 'photos'])
            ->where('FMR_ID', $farmer->FMR_ID)
            ->orderByDesc('LST_CREATED_AT')
            ->get()
            ->map(fn ($listing) => $this->formatListing($listing));

        return response()->json(['listings' => $listings]);
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

    private function uniqueId($table, $column): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }
}
