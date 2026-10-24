<?php

namespace App\Observers;

use App\Models\Listing;
use App\Services\PremiumAlertService;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class PremiumListingObserver
{
    public function created(Listing $listing): void
    {
        $this->dispatch($listing, 'new', 'created');
    }

    public function updated(Listing $listing): void
    {
        if ($listing->LST_STATUS !== 'AVAILABLE_NOW' || $listing->LST_AVAILABILITY !== 'ACTIVE') {
            return;
        }
        if (($listing->wasChanged('LST_STATUS') && $listing->getOriginal('LST_STATUS') !== 'AVAILABLE_NOW') || ($listing->wasChanged('LST_AVAILABILITY') && $listing->getOriginal('LST_AVAILABILITY') !== 'ACTIVE')) {
            $this->dispatch($listing, 'available', (string) Str::uuid());
        }
    }

    private function dispatch(Listing $listing, string $event, string $key): void
    {
        $id = $listing->LST_ID;
        DB::afterCommit(function () use ($id, $event, $key) {
            try {
                app(PremiumAlertService::class)->listingChanged($id, $event, $key);
            } catch (\Throwable $e) {
                Log::error('Premium listing alert failed', ['listing' => $id, 'error' => $e->getMessage()]);
            }
        });
    }
}
