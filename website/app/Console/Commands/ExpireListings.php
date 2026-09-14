<?php

namespace App\Console\Commands;

use App\Models\Listing;
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
     */
    public function handle()
    {
        $count = Listing::where('LST_EXPIRY_DATE', '<', now())
            ->where('LST_STATUS', '!=', 'NOT_AVAILABLE')
            ->update(['LST_STATUS' => 'NOT_AVAILABLE']);

        $message = "[listings:expire] {$count} listing(s) expired to NOT_AVAILABLE";

        $this->info($message);
        Log::info($message);

        return 0;
    }
}