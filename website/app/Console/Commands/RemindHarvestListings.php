<?php

namespace App\Console\Commands;

use App\Models\CropCategory;
use App\Models\Listing;
use App\Models\UserNotification;
use App\Services\NotificationService;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;

/**
 * Tell sellers which of their crops are due to be harvested today or tomorrow.
 *
 * LST_HARVEST_DATE is the date a farmer expects produce to be ready. Nobody is
 * required to keep it accurate, and nothing else in the app acts on it, so
 * before this existed a date passed in silence: the crop simply did not appear,
 * and the only trace was a listing the farmer had to remember posting.
 *
 * Today-and-tomorrow is the window rather than "today". A reminder that fires
 * on the morning of the harvest is too late to plan transport for; the day
 * before is the last moment the farmer can still do something about it.
 *
 * Three decisions worth stating:
 *
 *   - At most one reminder per listing per day, for as long as its harvest date
 *     is inside the today-or-tomorrow window. This is de-duplicated on the day
 *     the row was written, NOT on the harvest date, and the difference matters:
 *     a crop due tomorrow is written today, so a harvest-date key would look for
 *     tomorrow's date against a row stamped today, never match, and re-remind
 *     every hour all day. Keying on the written date instead means a crop gets
 *     one "tomorrow" notice and one "today" notice on the morning it is due -
 *     which is the useful pair - and never a burst of duplicates in between.
 *
 *   - One inbox row per listing, so the farmer can see which crop is due. This is
 *     also why the rows are written with the push suppressed and a single
 *     combined alert sent per farmer afterwards.
 *
 *   - One push per farmer per run, always, even for a single listing. The
 *     expiring-listings command skips its summary push for one listing because
 *     that case already produced a push of its own. Nothing here pushes
 *     individually, so the combined alert is the only push this command sends
 *     and skipping it for a single crop would mean that farmer hears nothing.
 */
class RemindHarvestListings extends Command
{
protected $signature = 'listings:remind-harvest';

    protected $description = 'Remind sellers once about crops due to be harvested today or tomorrow';

    /**
     * The timezone "today" is decided in.
     *
     * config/app.php is UTC, and NOTIF_CREATED_AT is therefore written in UTC.
     * Left alone, a run at 03:00 in the Philippines would still think it was
     * yesterday: a crop due today would be announced as "tomorrow" on the
     * morning it is due, and the once-per-day de-duplication below would reset
     * at 08:00 local instead of midnight, so farmers would get a second copy of
     * the same reminder.
     *
     * Scoped to this command rather than fixed in config/app.php on purpose:
     * "today" is only ambiguous here, where the wording is baked into the
     * message. Every other date in the app is either an explicit date column or
     * an interval, and moving the global timezone would silently shift all of
     * them - including timestamps the database already holds in UTC.
     */
    private const TIMEZONE = 'Asia/Manila';

    public function handle()
    {
        $cropNames = CropCategory::pluck('CAT_NAME', 'CAT_ID');

        $today = Carbon::now(self::TIMEZONE)->startOfDay();
        $tomorrow = $today->copy()->addDay();
        $todayKey = $today->toDateString();

        // One query for every listing already reminded about, so the loop below
        // makes no per-listing database round trip. Keyed "listing|day written":
        // the same listing on two different days is two legitimate reminders,
        // the same listing twice on one day is a bug.
        $alreadyReminded = UserNotification::where('NOTIF_TYPE', 'HARVEST_REMINDER')
            ->whereNotNull('NOTIF_REF_ID')
            ->get(['NOTIF_REF_ID', 'NOTIF_CREATED_AT'])
            ->mapWithKeys(function ($notification) use ($todayKey) {
                // Read as UTC, because that is what wrote it, then moved into
                // the farmer's timezone before taking the date. For the eight
                // hours after local midnight the UTC date is still yesterday,
                // so comparing the raw timestamp against a Manila day would
                // never match and every one of those runs would re-notify.
                $writtenOn = Carbon::parse($notification->NOTIF_CREATED_AT, 'UTC')
                    ->setTimezone(self::TIMEZONE)
                    ->toDateString();

                return [$notification->NOTIF_REF_ID.'|'.$writtenOn => true];
            });

        $due = Listing::query()
            ->with('farmer.buyer.user')
            ->whereNotNull('LST_HARVEST_DATE')
            // Removed listings are not the seller's doing and they cannot act on
            // a harvest date, same as the expiry warning.
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->whereBetween('LST_HARVEST_DATE', [$todayKey, $tomorrow->toDateString()])
            ->get();

        $bySeller = [];
        $reminded = 0;

        foreach ($due as $listing) {
            $ownerId = $listing->farmer?->buyer?->user?->USR_ID;

            if (! $ownerId) {
                continue;
            }

            $harvestOn = Carbon::parse($listing->LST_HARVEST_DATE)->toDateString();

            // Keyed on the day this row was written, in the farmer's timezone,
            // so the hourly re-runs within one day find it and the next day's
            // run does not.
            if (isset($alreadyReminded[$listing->LST_ID.'|'.$todayKey])) {
                continue;
            }

            $crop = $cropNames[$listing->CAT_ID] ?? 'produce';

            $when = $harvestOn === $todayKey ? 'today' : 'tomorrow';

            try {
                // sendPush false: the combined alert below is this farmer's one
                // push for the run. The inbox row is still written here.
                app(NotificationService::class)->notify(
                    $ownerId,
                    'HARVEST_REMINDER',
                    'Harvest reminder',
                    "Your {$crop} is expected to be ready {$when}. Update the listing when it is harvested.",
                    $listing->LST_ID,
                    sendPush: false,
                );

                $bySeller[$ownerId][] = $crop;
                $reminded++;
            } catch (\Throwable $e) {
                // One failed listing must not abort the run and cost every
                // other seller their reminder.
                Log::warning('[listings:remind-harvest] reminder failed', [
                    'lst_id' => $listing->LST_ID,
                    'usr_id' => $ownerId,
                    'message' => $e->getMessage(),
                ]);
            }
        }

        $service = app(NotificationService::class);

        foreach ($bySeller as $ownerId => $crops) {
            $count = count($crops);

            $body = $count === 1
                ? "{$crops[0]} is due for harvest. Open the app to update the listing."
                : "{$count} of your crops are due for harvest. Open the app to update them.";

            try {
                $service->pushOnly($ownerId, 'Crops due for harvest', $body);
            } catch (\Throwable $e) {
                // The inbox rows above are the source of truth and are already
                // committed; a failed push only costs the phone nudge.
                Log::warning('[listings:remind-harvest] combined push failed', [
                    'usr_id' => $ownerId,
                    'message' => $e->getMessage(),
                ]);
            }
        }

        $this->info(sprintf(
            '[listings:remind-harvest] %d listing(s) due within 2 days across %d seller(s), %d reminder(s) written',
            $due->count(),
            count($bySeller),
            $reminded,
        ));

        return 0;
    }
}