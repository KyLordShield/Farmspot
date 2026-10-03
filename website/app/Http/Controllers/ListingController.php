<?php

namespace App\Http\Controllers;

use App\Models\CropCategory;
use App\Models\Listing;
use App\Services\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class ListingController extends Controller
{
    public function index(Request $request)
    {
        $listings = Listing::with(['farmer.buyer.user', 'farm', 'category'])
            ->when($request->filled('search'), function ($query) use ($request) {
                $query->where(function ($q) use ($request) {
                    $q->where('LST_ID', 'like', '%' . $request->search . '%')
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

        $categories = CropCategory::orderBy('CAT_NAME')->get();

        return view('listings', compact('listings', 'categories'));
    }

    public function show($id)
    {
        $listing = Listing::with(['farmer.buyer.user', 'farm', 'category'])
            ->where('LST_ID', $id)
            ->firstOrFail();

        return view('listings.show', compact('listing'));
    }

    public function edit($id)
    {
        $listing = Listing::with(['farmer.buyer.user', 'farm', 'category'])
            ->where('LST_ID', $id)
            ->firstOrFail();

        $categories = CropCategory::orderBy('CAT_NAME')->get();

        return view('listings.edit', compact('listing', 'categories'));
    }

    public function update(Request $request, $id)
    {
        $listing = Listing::where('LST_ID', $id)->firstOrFail();

        $validated = $request->validate([
            'LST_CROP_ICON' => ['nullable', 'string', 'max:255'],
            'LST_STATUS' => ['required', 'in:AVAILABLE_NOW,SOON_TO_HARVEST,NOT_AVAILABLE'],
            'LST_AVAILABILITY' => ['required', 'in:ACTIVE,NOT_AVAILABLE,REMOVED'],
            'LST_HARVEST_DATE' => ['nullable', 'date'],
            'CAT_ID' => ['required', 'exists:crop_category,CAT_ID'],
        ]);

        // Read before the write, so the notification below can tell a genuine
        // takedown from re-submitting the form for a listing that was already
        // off sale.
        $previousAvailability = $listing->LST_AVAILABILITY;

        $listing->update([
            'LST_CROP_ICON' => $validated['LST_CROP_ICON'],
            'LST_STATUS' => $validated['LST_STATUS'],
            'LST_AVAILABILITY' => $validated['LST_AVAILABILITY'],
            'LST_HARVEST_DATE' => $validated['LST_HARVEST_DATE'],
            'CAT_ID' => $validated['CAT_ID'],
            'LST_UPDATED_AT' => now(),
        ]);

        $this->notifyIfRemovedByModerator($listing, $previousAvailability);

        return redirect()->route('listings')->with('success', 'Listing updated successfully.');
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