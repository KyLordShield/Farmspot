<?php

namespace App\Http\Controllers;

use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Listing;
use App\Services\NotificationService;
use App\Support\CloudinaryImage;
use App\Support\InputLimits;
use App\Support\ListingName;
use App\Support\PhotoLimits;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class ListingController extends Controller
{
    public function index(Request $request)
    {
        $listings = Listing::with(['farmer.buyer.user', 'farm', 'category'])
            ->when($request->filled('search'), function ($query) use ($request) {
                $query->where(function ($q) use ($request) {
                    $q->where('LST_ID', 'like', '%' . $request->search . '%')
                      ->orWhere('LST_CROP_ICON', 'like', '%' . $request->search . '%')
                      ->orWhereHas('category', function ($cq) use ($request) {
                          $cq->where('CAT_NAME', 'like', '%' . $request->search . '%');
                      })
                      ->orWhereHas('farm', function ($fq) use ($request) {
                          $fq->where('FRM_NAME', 'like', '%' . $request->search . '%');
                      });
                });
            })
            ->when($request->filled('category'), function ($query) use ($request) {
                $query->where('CAT_ID', $request->category);
            })
            ->when($request->filled('status'), function ($query) use ($request) {
                $query->where('LST_AVAILABILITY', $request->status);
            })
            ->orderBy('LST_CREATED_AT', 'desc')
            ->paginate(10)
            ->withQueryString();

        return view('listings', [
            'listings' => $listings,
            // withCount on all three referencing tables, because the category
            // panel disables delete on any of them. Counting listings alone would
            // light the button up green on a category that analytics rows still
            // point at, and the delete would come back as a foreign key error.
            'categories' => $this->categoriesForPanel(),
        ]);
    }

    /**
     * Every category, with how many rows still reference it.
     *
     * Ordered by name because that is the order the panel lists them in and the
     * order the filter dropdown above the table uses.
     */
    private function categoriesForPanel()
    {
        return CropCategory::withCount(['listings', 'insights', 'trends'])
            ->orderBy('CAT_NAME')
            ->get();
    }

    public function show($id)
    {
        $listing = Listing::with(['farmer.buyer.user', 'farm', 'category', 'photos'])
            ->where('LST_ID', $id)
            ->firstOrFail();

        return view('listings.show', compact('listing'));
    }

    public function create()
    {
        $listing = new Listing(['LST_STATUS' => 'AVAILABLE_NOW']);
        $categories = CropCategory::orderBy('CAT_NAME')->get();
        $farms = Farm::with('farmer.buyer.user')
            ->whereHas('farmer', fn ($query) => $query->where('FMR_SELLER_MODE_ACTIVE', 1))
            ->orderBy('FRM_NAME')->get();

        return view('listings.edit', compact('listing', 'categories', 'farms'));
    }

    public function store(Request $request)
    {
        return $this->saveListing($request);
    }

    public function edit($id)
    {
        $listing = Listing::with(['farmer.buyer.user', 'farm', 'photos'])->findOrFail($id);
        $categories = CropCategory::orderBy('CAT_NAME')->get();

        return view('listings.edit', compact('listing', 'categories'));
    }

    public function update(Request $request, $id)
    {
        return $this->saveListing($request, $id);
    }

    private function saveListing(Request $request, ?string $id = null)
    {
        $creating = $id === null;
        $validated = $request->validate([
            'LST_CROP_ICON' => [$creating ? 'required' : 'nullable', 'string', 'max:'.($creating ? InputLimits::CROP_NAME : 255)],
            'LST_DESCRIPTION' => ['nullable', 'string', 'max:'.InputLimits::DESCRIPTION],
            'LST_STATUS' => ['required', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
            'LST_AVAILABILITY' => [$creating ? 'prohibited' : 'required', 'in:ACTIVE,NOT_AVAILABLE,REMOVED'],
            'LST_HARVEST_DATE' => ['exclude_unless:LST_STATUS,SOON_TO_HARVEST', 'required', 'date_format:Y-m-d'],
            'CAT_ID' => ['required', 'exists:crop_category,CAT_ID'],
            'FRM_ID' => [$creating ? 'required' : 'prohibited', 'string'],
            'photos' => ['nullable', 'array', 'max:'.PhotoLimits::LISTING],
            'photos.*' => ['image', 'max:5120'],
            'remove_photos' => [$creating ? 'prohibited' : 'sometimes', 'array', 'max:'.PhotoLimits::LISTING],
            'remove_photos.*' => ['required', 'string', 'size:6', 'distinct'],
            'remove_legacy_photo' => [$creating ? 'prohibited' : 'sometimes', 'boolean'],
        ], [], [
            'LST_CROP_ICON' => 'crop name',
            'LST_DESCRIPTION' => 'description',
            'LST_STATUS' => 'crop status',
            'LST_AVAILABILITY' => 'listing availability',
            'LST_HARVEST_DATE' => 'harvest date',
            'CAT_ID' => 'category',
            'FRM_ID' => 'farm',
            'photos.*' => 'photo',
        ]);

        $uploads = [];
        $removedUrls = [];
        try {
            [$listing, $previousAvailability] = DB::transaction(function () use ($id, $creating, $validated, &$uploads, &$removedUrls) {
                $listing = $creating ? new Listing : Listing::findOrFail($id);
                $farm = Farm::whereKey($creating ? $validated['FRM_ID'] : $listing->FRM_ID)
                    ->lockForUpdate()->first();
                if ($creating && (int) $farm?->farmer?->FMR_SELLER_MODE_ACTIVE !== 1) {
                    throw ValidationException::withMessages(['FRM_ID' => 'Choose a farm with an active seller.']);
                }

                if (! $creating) {
                    $listing = Listing::lockForUpdate()->findOrFail($id);
                }

                $fields = Arr::except($validated, ['FRM_ID', 'photos', 'remove_photos', 'remove_legacy_photo']);
                $name = $fields['LST_CROP_ICON'] ?? null;
                if ($creating || (filled($name) && $name !== $listing->LST_CROP_ICON && $farm)) {
                    try {
                        ListingName::ensureUnique($farm->FRM_ID, $name, $id);
                    } catch (HttpResponseException $exception) {
                        throw ValidationException::withMessages([
                            'LST_CROP_ICON' => $exception->getResponse()->getData()->message,
                        ]);
                    }
                }

                $previousAvailability = $listing->LST_AVAILABILITY;
                if ($creating) {
                    $listing->forceFill([
                        'LST_ID' => $this->uniqueId('listing', 'LST_ID'),
                        'FMR_ID' => $farm->FMR_ID,
                        'FRM_ID' => $farm->FRM_ID,
                        'LST_AVAILABILITY' => 'ACTIVE',
                        'LST_CREATED_AT' => now(),
                        'LST_EXPIRY_DATE' => now()->addDays(3),
                    ]);
                }

                $listing->fill($fields);
                $listing->LST_UPDATED_AT = now();
                $listing->save();

                if (!$creating) {
                    $this->removeSelectedPhotos($listing, $validated['remove_photos'] ?? [], (bool) ($validated['remove_legacy_photo'] ?? false), $removedUrls);
                }

                if (! empty($validated['photos'])) {
                    $this->appendPhotos($listing, $validated['photos'], $uploads);
                }

                return [$listing, $previousAvailability];
            });
        } catch (\Throwable $exception) {
            foreach ($uploads as $url) {
                CloudinaryImage::deleteByUrl($url);
            }

            throw $exception;
        }

        // Only clean up storage after the entire save (including uploads) commits.
        foreach (array_unique($removedUrls) as $url) {
            if (!\App\Models\ListingPhoto::where('LPHOTO_FILE_PATH', $url)->exists()
                && !Listing::where('LST_IMAGE', $url)->exists()) {
                CloudinaryImage::deleteByUrl($url);
            }
        }
        $this->notifyIfRemovedByModerator($listing, $previousAvailability);

        return redirect()->route('listings.show', $listing->LST_ID)
            ->with('success', $creating ? 'Listing added successfully.' : 'Listing updated successfully.');
    }

    private function removeSelectedPhotos(Listing $listing, array $ids, bool $legacy, array &$removedUrls): void
    {
        if ($ids === [] && !$legacy) return;
        $photos = $listing->photos()->lockForUpdate()->get();
        $selected = $photos->whereIn('LPHOTO_ID', $ids);
        if ($selected->count() !== count($ids)
            || ($legacy && ($photos->isNotEmpty() || blank($listing->LST_IMAGE)))) {
            throw ValidationException::withMessages(['remove_photos' => 'The selected photos have changed or do not belong to this listing. Reload and try again.']);
        }
        if ($legacy) {
            $removedUrls[] = $listing->LST_IMAGE;
            $listing->update(['LST_IMAGE' => null]);
            return;
        }
        foreach ($selected as $photo) {
            $removedUrls[] = $photo->LPHOTO_FILE_PATH;
            $photo->delete();
        }
        $remaining = $photos->whereNotIn('LPHOTO_ID', $ids);
        $primary = $remaining->firstWhere('LPHOTO_IS_PRIMARY', 1) ?? $remaining->first();
        $listing->photos()->update(['LPHOTO_IS_PRIMARY' => 0]);
        $primary?->update(['LPHOTO_IS_PRIMARY' => 1]);
        $listing->update(['LST_IMAGE' => $primary?->LPHOTO_FILE_PATH]);
    }

    private function appendPhotos(Listing $listing, array $photos, array &$uploads): void
    {
        $existing = $listing->photos()->count();
        $legacyPhoto = $existing === 0 ? $listing->LST_IMAGE : null;
        PhotoLimits::ensure($existing + (int) filled($legacyPhoto), count($photos), PhotoLimits::LISTING, 'listing');

        if ($legacyPhoto) {
            $this->addPhotoRow($listing, $legacyPhoto, true);
            $existing++;
        }

        $disk = Storage::disk('cloudinary');
        foreach ($photos as $photo) {
            $path = "listing-photos/{$listing->LST_ID}/".Str::uuid().'.'.$photo->extension();
            if (! $disk->put($path, $photo->getRealPath())) {
                throw ValidationException::withMessages(['photos' => 'The photos could not be uploaded. Try again.']);
            }

            $url = $disk->url($path);
            $uploads[] = $url;
            $primary = $existing === 0;
            $this->addPhotoRow($listing, $url, $primary);
            if ($primary) {
                $listing->update(['LST_IMAGE' => $url]);
            }
            $existing++;
        }
    }

    private function addPhotoRow(Listing $listing, string $url, bool $primary): void
    {
        $listing->photos()->create([
            'LPHOTO_ID' => $this->uniqueId('listing_photo', 'LPHOTO_ID'),
            'LPHOTO_FILE_PATH' => $url,
            'LPHOTO_IS_PRIMARY' => $primary,
            'LPHOTO_UPLOADED_AT' => now(),
        ]);
    }

    private function uniqueId(string $table, string $column): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }

    public function destroy($id)
    {
        $listing = Listing::where('LST_ID', $id)->firstOrFail();

        $previousAvailability = $listing->LST_AVAILABILITY;

        $listing->LST_AVAILABILITY = 'REMOVED';
        $listing->LST_UPDATED_AT = now();
        $listing->save();

        $this->notifyIfRemovedByModerator($listing, $previousAvailability);

        return redirect()->route('listings')->with('success', 'Listing removed successfully.');
    }

    /**
     * Tell the seller when a moderator takes their listing off sale.
     *
     * A takedown is invisible from the seller's side: their crop simply stops
     * appearing in the app, with no reason given, and the app has no inbox
     * message until this. That silence is the difference between "I sold out"
     * and "I was removed", and a farmer who cannot tell the two apart will
     * assume the worst about their own account.
     *
     * The comparison is against the value before this request, not against
     * 'REMOVED', because update() and destroy() can both be re-run on a listing
     * that is already off sale — re-submitting the edit form, or a moderator
     * clicking Remove twice. Firing again would tell the same seller their
     * listing was removed a second time for something already done.
     *
     * Deliberately not fired when a moderator restores a listing back to ACTIVE,
     * and not fired for a listing whose owner is no longer resolvable.
     */
    private function notifyIfRemovedByModerator(Listing $listing, ?string $previousAvailability): void
    {
        if ($listing->LST_AVAILABILITY !== 'REMOVED' || $previousAvailability === 'REMOVED') {
            return;
        }

        $ownerId = $this->ownerUserId($listing);

        if ($ownerId === null) {
            return;
        }

        $crop = $listing->category?->CAT_NAME ?? 'produce';

        // The listing is already saved as REMOVED by the time this runs, so the
        // removal must not be reported as failed just because OneSignal or the
        // notification insert had a bad moment.
        try {
            app(NotificationService::class)->notify(
                $ownerId,
                'LISTING_REMOVED',
                'Listing no longer on sale',
                // Deliberately says nothing about where to go. This type is
                // non-tappable on purpose - the listing is gone from the feed
                // AND from My Farm, so there is nowhere to open - and the old
                // "Open it to see the details" pointed at a screen that cannot
                // load and left farmers convinced the app was broken.
                "Your {$crop} listing was taken down by our team and is no longer on sale.",
                $listing->LST_ID,
            );
        } catch (\Throwable $e) {
            Log::warning('[notifications] listing removed notification failed', [
                'lst_id' => $listing->LST_ID,
                'usr_id' => $ownerId,
                'message' => $e->getMessage(),
            ]);
        }
    }

    /**
     * The user who posted this listing.
     *
     * A listing belongs to a farmer, not to a person, and a farmer is a row
     * hanging off a buyer, which hangs off a user — so the walk is
     * listing -> farmer -> buyer -> user. Returns null when any link is broken,
     * because there is nobody to notify in that case.
     */
    private function ownerUserId(Listing $listing): ?string
    {
        return Listing::join('farmer', 'farmer.FMR_ID', '=', 'listing.FMR_ID')
            ->join('buyer', 'buyer.BUY_ID', '=', 'farmer.BUY_ID')
            ->where('listing.LST_ID', $listing->LST_ID)
            ->value('buyer.USR_ID');
    }
}
