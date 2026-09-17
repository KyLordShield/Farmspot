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

/**
 * Multi-photo gallery management for a listing. listing_photo is the source of
 * truth for the gallery; listing.LST_IMAGE is a denormalized cache of the
 * current primary photo's URL, kept in sync here so the existing single-image
 * read paths (buyer feed, farm profile, thumbnails) keep working unchanged.
 */
class ListingPhotoController extends Controller
{
    use FormatsListings;

    /**
     * Append one or more photos to a listing's gallery (append-only).
     * If the listing has no photos yet, the first uploaded photo is
     * auto-promoted to primary so a gallery always has a thumbnail.
     */
    public function store(Request $request, $listingId)
    {
        [$listing, $error] = $this->resolveOwnedListing($request, $listingId);

        if ($error) {
            return $error;
        }

        $validated = $request->validate([
            'photos' => ['required', 'array', 'min:1'],
            'photos.*' => ['image', 'max:5120'],
        ]);

        $isFirstEver = ! ListingPhoto::where('LST_ID', $listing->LST_ID)->exists();

        try {
            DB::transaction(function () use ($validated, $listing, $isFirstEver) {
                foreach ($validated['photos'] as $index => $photo) {
                    $extension = $photo->getClientOriginalExtension() ?: 'jpg';
                    $path = "listing-photos/{$listing->LST_ID}/" . uniqid() . ".{$extension}";

                    Storage::disk('cloudinary')->put($path, $photo->getRealPath());
                    $url = Storage::disk('cloudinary')->url($path);

                    $isPrimary = $isFirstEver && $index === 0;

                    ListingPhoto::create([
                        'LPHOTO_ID' => $this->uniqueId('listing_photo', 'LPHOTO_ID'),
                        'LPHOTO_FILE_PATH' => $url,
                        'LPHOTO_UPLOADED_AT' => now(),
                        'LPHOTO_IS_PRIMARY' => $isPrimary ? 1 : 0,
                        'LST_ID' => $listing->LST_ID,
                    ]);

                    if ($isPrimary) {
                        $this->syncThumbnail($listing, $url);
                    }
                }
            });
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'Failed to upload listing photos.',
            ], 500);
        }

        return response()->json([
            'message' => 'Listing photos uploaded successfully.',
            'listing' => $this->formatListing($this->freshListing($listing->LST_ID)),
        ], 201);
    }

    /**
     * Mark one gallery photo as the listing's primary/thumbnail. Exactly one
     * photo per listing has LPHOTO_IS_PRIMARY = 1; LST_IMAGE is re-pointed.
     */
    public function setPrimary(Request $request, $listingId, $photoId)
    {
        [$listing, $error] = $this->resolveOwnedListing($request, $listingId);

        if ($error) {
            return $error;
        }

        $photo = ListingPhoto::where('LST_ID', $listing->LST_ID)
            ->where('LPHOTO_ID', $photoId)
            ->first();

        if (! $photo) {
            return response()->json([
                'message' => 'Photo not found on this listing.',
            ], 404);
        }

        DB::transaction(function () use ($listing, $photo) {
            ListingPhoto::where('LST_ID', $listing->LST_ID)
                ->update(['LPHOTO_IS_PRIMARY' => 0]);

            $photo->LPHOTO_IS_PRIMARY = 1;
            $photo->save();

            $this->syncThumbnail($listing, $photo->LPHOTO_FILE_PATH);
        });

        return response()->json([
            'message' => 'Primary photo updated successfully.',
            'listing' => $this->formatListing($this->freshListing($listing->LST_ID)),
        ]);
    }

    /**
     * Delete one gallery photo. If it was the primary, the oldest remaining
     * photo is auto-promoted (LST_IMAGE updated to match); if no photos
     * remain, LST_IMAGE becomes null. The Cloudinary asset is destroyed.
     */
    public function destroy(Request $request, $listingId, $photoId)
    {
        [$listing, $error] = $this->resolveOwnedListing($request, $listingId);

        if ($error) {
            return $error;
        }

        $photo = ListingPhoto::where('LST_ID', $listing->LST_ID)
            ->where('LPHOTO_ID', $photoId)
            ->first();

        if (! $photo) {
            return response()->json([
                'message' => 'Photo not found on this listing.',
            ], 404);
        }

        $wasPrimary = (int) $photo->LPHOTO_IS_PRIMARY === 1;
        $deletedUrl = $photo->LPHOTO_FILE_PATH;

        DB::transaction(function () use ($listing, $photo, $wasPrimary) {
            $photo->delete();

            if ($wasPrimary) {
                $next = ListingPhoto::where('LST_ID', $listing->LST_ID)
                    ->orderBy('LPHOTO_UPLOADED_AT')
                    ->orderBy('LPHOTO_ID')
                    ->first();

                if ($next) {
                    $next->LPHOTO_IS_PRIMARY = 1;
                    $next->save();

                    $this->syncThumbnail($listing, $next->LPHOTO_FILE_PATH);
                } else {
                    $this->syncThumbnail($listing, null);
                }
            }
        });

        CloudinaryImage::deleteByUrl($deletedUrl);

        return response()->json([
            'message' => 'Listing photo deleted successfully.',
            'listing' => $this->formatListing($this->freshListing($listing->LST_ID)),
        ]);
    }

    /**
     * Resolve the listing and enforce that the authenticated seller owns it.
     * Returns [Listing, null] on success or [null, JsonResponse] on failure.
     */
    private function resolveOwnedListing(Request $request, $listingId): array
    {
        $listing = Listing::find($listingId);

        if (! $listing) {
            return [null, response()->json(['message' => 'Listing not found.'], 404)];
        }

        $farmer = $request->user()->buyer?->farmer;

        if (! $farmer || $listing->FMR_ID !== $farmer->FMR_ID) {
            return [null, response()->json(['message' => 'You do not own this listing.'], 403)];
        }

        return [$listing, null];
    }

    /**
     * Update the denormalized LST_IMAGE thumbnail cache. Pass null to clear it
     * when the last gallery photo is removed.
     */
    private function syncThumbnail(Listing $listing, ?string $url): void
    {
        $listing->LST_IMAGE = $url;
        $listing->LST_UPDATED_AT = now();
        $listing->save();
    }

    private function freshListing($listingId): Listing
    {
        return Listing::with(['farm', 'category', 'photos'])->find($listingId);
    }

    private function uniqueId($table, $column): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }
}
