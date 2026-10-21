<?php

namespace App\Console\Commands;

use App\Models\CropCategory;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\UserNotification;
use App\Services\NotificationService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class ExpireListings extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'listings:expire';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Notify sellers whose listing has passed its three-day freshness window';

    /**
     * Execute the console command.
     *
     * Expired listings stay visible on Home, in Search, and on the detail
     * screen. The buyer-facing warning on the detail screen already tells
     * shoppers the crop may not be as fresh, and the seller needs the listing
     * to remain in the app so they can renew it with fresh photos. Flipping it
     * to NOT_AVAILABLE here would silently remove it from every buyer surface.
     * Only the owner notification is sent.
     *
     * On-sale rows (AVAILABLE_NOW) whose expiry is in the past are reported.
     * LST_AVAILABILITY (the admin-moderation field) is deliberately left alone,
     * and LST_EXPIRY_DATE is kept as-is to record when the listing expired.
     *
     * SOON_TO_HARVEST is deliberately excluded. It is not on sale yet, so its
     * three-day window has not started; a crop harvested two weeks from now
     * must not be reported as expired three days after it was posted.
     * listings:harvest starts that window when the harvest date arrives.
     *
     * A listing a moderator has already taken down is skipped entirely. It is
     * not on sale, the farmer cannot act on it, and rewriting its LST_STATUS
     * would quietly erase the record of why it disappeared.
     *
     * The farm pin is never touched. Expiry is about one crop going stale, not
     * about the farm closing for business.
     */
    public function handle()
    {
        $cropNames = CropCategory::pluck('CAT_NAME', 'CAT_ID');

        // Fetched rather than blind-updated, because each expired listing needs
        // its owner named in the notification and there is no way to say "you
        // posted this" without knowing who that is.
        $expired = Listing::with('farmer.buyer.user')
            ->where('LST_EXPIRY_DATE', '<', now())
            ->where('LST_STATUS', 'AVAILABLE_NOW')
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->get();

        foreach ($expired as $listing) {
            $this->notifyExpiredOwner($listing, $cropNames);
        }

        $message = "[listings:expire] {$expired->count()} listing(s) reported expired (kept visible)";

        $this->info($message);
        Log::info($message);

        return 0;
    }

    /**
     * Tell the seller their listing timed out, once per listing.
     *
     * Expiry happens to the farmer rather than by their choice, so without this
     * the only clue they get is that their crop is gone from the app. The
     * wording says what happened and what to do next, because "your listing
     * expired" on its own just reads as a rejection.
     *
     * NOTIF_TYPE + NOTIF_REF_ID is checked first: this command runs hourly and
     * may be re-run by hand, and a listing whose expiry was pushed into the
     * future by a status update can come back through here again. Telling
     * someone their cabbage expired twice is worse than not telling them at all.
     */
    private function notifyExpiredOwner(Listing $listing, $cropNames): void
    {
        $ownerId = $listing->farmer?->buyer?->user?->USR_ID
            // Fallback to a joined lookup. With the relation loaded above this
            // is nearly always already resolved; the query is here for the case
            // where the chain is present but a relation was not hydrated.
            ?? Farmer::join('buyer', 'buyer.BUY_ID', '=', 'farmer.BUY_ID')
                ->where('farmer.FMR_ID', $listing->FMR_ID)
                ->value('buyer.USR_ID');

        if (! $ownerId) {
            return;
        }

        $alreadyTold = UserNotification::where('NOTIF_TYPE', 'LISTING_EXPIRED')
            ->where('NOTIF_REF_ID', $listing->LST_ID)
            ->exists();

        if ($alreadyTold) {
            return;
        }

        // The crop the farmer typed names the listing; the category is only a
        // fallback for a blank name, since "your Vegetable expired" does not say
        // which crop to update.
        $crop = $listing->LST_CROP_ICON ?: ($cropNames[$listing->CAT_ID] ?? 'produce');

        app(NotificationService::class)->notify(
            $ownerId,
            'LISTING_EXPIRED',
            'Listing expired',
            "Your {$crop} listing is past its three-day freshness window. Renew it with a fresh photo to show buyers it is still fresh.",
            $listing->LST_ID,
        );
    }
}