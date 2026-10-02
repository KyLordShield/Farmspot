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
    protected $description = 'Flip listings whose expiry date has passed to NOT_AVAILABLE';

    /**
     * Execute the console command.
     *
     * Only listings that genuinely need updating are touched: expiries in the
     * past whose status is not already NOT_AVAILABLE. LST_AVAILABILITY (the
     * admin-moderation field) is deliberately left alone, and LST_EXPIRY_DATE
     * is kept as-is to record when the listing actually expired.
     *
     * A listing a moderator has already taken down is skipped entirely. It is
     * not on sale, the farmer cannot act on it, and flipping its LST_STATUS
     * would quietly rewrite the record of why it disappeared — it now looks
     * like it simply sold out or timed out rather than being removed by
     * moderation.
     *
     * The farm pin is never touched. Expiry is about one crop going stale, not
     * about the farm closing for business, and hiding the pin would remove a
     * farmer's other, perfectly good produce from the map because an unrelated
     * listing timed out.
     */
    public function handle()
    {
        $cropNames = CropCategory::pluck('CAT_NAME', 'CAT_ID');

        // Fetched rather than blind-updated, because each expired listing needs
        // its owner named in the notification and there is no way to say "you
        // posted this" without knowing who that is.
        $expired = Listing::with('farmer.buyer.user')
            ->where('LST_EXPIRY_DATE', '<', now())
            ->where('LST_STATUS', '!=', 'NOT_AVAILABLE')
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->get();

        foreach ($expired as $listing) {
            $listing->LST_STATUS = 'NOT_AVAILABLE';
            $listing->LST_UPDATED_AT = now();
            $listing->save();

            $this->notifyExpiredOwner($listing, $cropNames);
        }

        $message = "[listings:expire] {$expired->count()} listing(s) expired to NOT_AVAILABLE";

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

        $crop = $cropNames[$listing->CAT_ID] ?? 'produce';

        app(NotificationService::class)->notify(
            $ownerId,
            'LISTING_EXPIRED',
            'Listing expired',
            "Your {$crop} listing is now marked Not Available. Update it to show it again.",
            $listing->LST_ID,
        );
    }
}