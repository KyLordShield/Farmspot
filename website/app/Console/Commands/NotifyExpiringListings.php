<?php

namespace App\Console\Commands;

use App\Models\CropCategory;
use App\Models\Listing;
use App\Models\UserNotification;
use App\Services\NotificationService;
use Illuminate\Console\Command;

/**
 * Warn sellers about listings that are about to expire, and tell them once.
 *
 * The three-day listing rule expires a crop automatically, and until this
 * existed the farmer only found out because their produce quietly disappeared
 * from the feed. A listing that has not sold and simply rolled off is the most
 * common and least explicable thing that happens to a seller, so it gets a
 * warning a day ahead.
 *
 * Two decisions worth stating:
 *
 *   - One warning per listing, ever. Checked against NOTIF_REF_ID rather than a
 *     timestamp window, because this runs hourly for the life of the listing and
 *     a listing can sit inside the 24-hour window across several runs. A
 *     timestamp check would need care to avoid either double-warning or
 *     warning too late.
 *
 *   - One push per farmer per run, however many of their listings are expiring.
 *     The inbox still gets a row per listing, because the app lists them
 *     individually and the farmer needs to know which crops to update. The push
 *     is combined ("3 of your listings expire within 24 hours") because a
 *     seller with several listings close to expiry would otherwise get a burst
 *     of separate alerts, and on a weak rural connection a burst of pushes is
 *     indistinguishable from spam and tends to get notifications turned off
 *     entirely.
 */
class NotifyExpiringListings extends Command
{
    protected $signature = 'listings:notify-expiring';

    protected $description = 'Warn sellers once about listings that expire within the next 24 hours';

    public function handle()
    {
        $cropNames = CropCategory::pluck('CAT_NAME', 'CAT_ID');

        // Which listings does this user already have a warning for? Resolved in
        // one query so the loop below makes no per-listing round trip.
        $alreadyWarned = UserNotification::where('NOTIF_TYPE', 'LISTING_EXPIRING_SOON')
            ->whereNotNull('NOTIF_REF_ID')
            ->pluck('NOTIF_REF_ID')
            ->flip();

        $due = Listing::query()
            ->with('farmer.buyer.user')
            ->where('LST_STATUS', '!=', 'NOT_AVAILABLE')
            // Admin-moderated out listings are not the seller's doing and the
            // farmer cannot act on the warning, so they are skipped.
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->where('LST_EXPIRY_DATE', '>', now())
            ->where('LST_EXPIRY_DATE', '<=', now()->addDay())
            ->get();

        $bySeller = [];

        foreach ($due as $listing) {
            if (isset($alreadyWarned[$listing->LST_ID])) {
                continue;
            }

            $ownerId = $listing->farmer?->buyer?->user?->USR_ID;

            if (! $ownerId) {
                continue;
            }

            $crop = $cropNames[$listing->CAT_ID] ?? 'produce';

            // Stored per listing: the inbox row is the record of which crop was
            // actually warned about.
            app(NotificationService::class)->notify(
                $ownerId,
                'LISTING_EXPIRING_SOON',
                'Listing expiring soon',
                "Your {$crop} listing expires in less than a day. Update it to keep it showing in the app.",
                $listing->LST_ID,
            );

            $bySeller[$ownerId][] = $crop;
        }

        // The combined push. Sent after the loop so the counts are complete.
        // Only for sellers who had more than one listing expiring — a single one
        // already got its own push above, and sending a second, vaguer alert for
        // the same event is just noise.
        $service = app(NotificationService::class);

        foreach ($bySeller as $ownerId => $crops) {
            if (count($crops) < 2) {
                continue;
            }

            $count = count($crops);

            // pushOnly, not notify: the inbox rows above are already one per
            // listing, and a summary row with no NOTIF_REF_ID would sit in the
            // list pointing at no particular crop.
            $service->pushOnly(
                $ownerId,
                'Listings expiring soon',
                "{$count} of your listings expire in less than a day. Open the app to update them.",
            );
        }

        $message = sprintf(
            '[listings:notify-expiring] %d listing(s) expiring within 24h across %d seller(s)',
            $due->count(),
            count($bySeller),
        );

        $this->info($message);

        return 0;
    }
}