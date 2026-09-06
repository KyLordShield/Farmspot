<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Listing;
use App\Support\CloudinaryImage;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class FarmerListingController extends Controller
{
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

        $listings = Listing::with(['farm', 'category'])
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

        $listing = Listing::with(['farm', 'category'])
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
     * POST /api/listings/{id}/photo instead.
     */
    public function update(Request $request, $listingId)
    {
        $listing = Listing::with(['farm', 'category'])->find($listingId);

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
            'harvest_date' => ['nullable', 'date'],
            'status' => ['nullable', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
        ]);

        if (array_key_exists('category_id', $validated)) {
            $listing->CAT_ID = $validated['category_id'];
        }

        if (array_key_exists('crop_icon', $validated)) {
            $listing->LST_CROP_ICON = $validated['crop_icon'];
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

        $fresh = Listing::with(['farm', 'category'])->find($listing->LST_ID);

        return response()->json([
            'message' => 'Listing updated successfully.',
            'listing' => $this->formatListing($fresh),
        ]);
    }

    /**
     * Replace the photo of one of the farmer's own listings. POST makes the
     * multipart upload actually land (PHP only parses multipart for POST).
     * The new image is uploaded to Cloudinary exactly like POST /api/listings
     * does; once the row points at it, the old cloud asset is destroyed.
     */
    public function uploadPhoto(Request $request, $listingId)
    {
        $listing = Listing::with(['farm', 'category'])->find($listingId);

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

        $oldImage = $listing->LST_IMAGE;
        $listing->LST_IMAGE = Storage::disk('cloudinary')->url($path);
        $listing->LST_UPDATED_AT = now();
        $listing->save();

        // Destroy the old asset only AFTER the new one was uploaded and the row
        // has switched over, so a failed upload never loses the listing photo.
        CloudinaryImage::deleteByUrl($oldImage);

        $fresh = Listing::with(['farm', 'category'])->find($listing->LST_ID);

        return response()->json([
            'message' => 'Listing photo updated successfully.',
            'listing' => $this->formatListing($fresh),
        ]);
    }

    /**
     * Hard-delete one of the farmer's own listings (auth + ownership required).
     * Also destroys the listing's Cloudinary image if one exists, so no cloud
     * asset is orphaned by the DB row going away.
     */
    public function destroy(Request $request, $listingId)
    {
        $listing = Listing::find($listingId);

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

        CloudinaryImage::deleteByUrl($listing->LST_IMAGE);

        $listing->delete();

        return response()->json([
            'message' => 'Listing deleted successfully.',
            'deleted_id' => $listing->LST_ID,
        ]);
    }

    /**
     * Shape a Listing model into the same flat JSON structure the buyer feed
     * uses, so the farmer-facing screens share a consistent contract.
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
}
