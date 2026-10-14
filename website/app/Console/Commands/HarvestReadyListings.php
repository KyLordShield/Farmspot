<?php

namespace App\Console\Commands;

use App\Models\CropCategory;
use App\Models\Listing;
use App\Services\NotificationService;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;

class HarvestReadyListings extends Command
{
    protected $signature = 'listings:harvest';

    protected $description = 'Flip SOON_TO_HARVEST listings to AVAILABLE_NOW when their harvest date has arrived';

    private const TIMEZONE = 'Asia/Manila';

    public function handle()
    {
        $cropNames = CropCategory::pluck('CAT_NAME', 'CAT_ID');
        $today = Carbon::now(self::TIMEZONE)->startOfDay()->toDateString();

        $ready = Listing::query()
            ->with('farmer.buyer.user')
            ->where('LST_STATUS', 'SOON_TO_HARVEST')
            ->where('LST_AVAILABILITY', 'ACTIVE')
            ->whereNotNull('LST_HARVEST_DATE')
            ->where('LST_HARVEST_DATE', '<=', $today)
            ->get();

        $flipped = 0;

        foreach ($ready as $listing) {
            // Flip first and unconditionally. The status change is what stops
            // the row matching this query on the next run, so the command is
            // idempotent by virtue of the flip itself. The notification must
            // never gate it: checking "have we already told them?" before the
            // write left any listing that already had a LISTING_AVAILABLE row
            // stuck on SOON_TO_HARVEST forever, which is exactly the state a
            // farmer lands in after moving a crop back to Soon to Harvest.
            $listing->LST_STATUS = 'AVAILABLE_NOW';
            $listing->LST_EXPIRY_DATE = now()->addDays(3);
            $listing->LST_UPDATED_AT = now();
            $listing->save();

            $flipped++;

            $ownerId = $listing->farmer?->buyer?->user?->USR_ID;

            if (! $ownerId) {
                continue;
            }

            // The name the farmer typed is what makes the notice actionable:
            // LST_CROP_ICON ("Cabbage") names the crop, while the category
            // ("Vegetable") is too broad to tell which of several crops is the
            // one that just went live. Falls back to the category only when the
            // crop name is blank.
            $crop = $listing->LST_CROP_ICON ?: ($cropNames[$listing->CAT_ID] ?? 'produce');

            try {
                app(NotificationService::class)->notify(
                    $ownerId,
                    'LISTING_AVAILABLE',
                    'Listing available',
                    "Your {$crop} is now available. Buyers can contact you.",
                    $listing->LST_ID,
                );
            } catch (\Throwable $e) {
                // The flip is already committed and is the part the buyer feed
                // depends on; a failed notification only costs the nudge.
                Log::warning('[listings:harvest] notification failed', [
                    'lst_id' => $listing->LST_ID,
                    'usr_id' => $ownerId,
                    'message' => $e->getMessage(),
                ]);
            }
        }

        $this->info(sprintf('[listings:harvest] %d listing(s) flipped to AVAILABLE_NOW', $flipped));
        Log::info(sprintf('[listings:harvest] %d listing(s) flipped to AVAILABLE_NOW', $flipped));

        return 0;
    }
}
