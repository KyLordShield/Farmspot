<?php

namespace App\Services;

use App\Models\BuyRequest;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class PremiumAlertService
{
    public static function settings(string $userId): array
    {
        $row = DB::table('premium_alert_setting')->where('USR_ID', $userId)->first();

        return ['enabled' => (bool) ($row->ALERTS_ENABLED ?? true), 'saved_farms' => (bool) ($row->SAVED_FARM_ALERTS ?? true), 'buy_requests' => (bool) ($row->BUY_REQUEST_ALERTS ?? true), 'crop_alerts' => (bool) ($row->CROP_ALERTS ?? true), 'crops' => $row?->ALERT_CROPS ? json_decode($row->ALERT_CROPS, true) : [],
            'push_enabled' => (bool) ($row->PUSH_ENABLED ?? false), 'push_frequency' => $row->PUSH_FREQUENCY ?? 'hourly',
            'quiet_enabled' => (bool) ($row->QUIET_ENABLED ?? true), 'quiet_start' => $row->QUIET_START ?? '22:00', 'quiet_end' => $row->QUIET_END ?? '07:00', 'daily_time' => $row->DAILY_TIME ?? '09:00'];
    }

    private function publicListing(Listing $listing): bool
    {
        return $listing->LST_AVAILABILITY === 'ACTIVE' && in_array($listing->LST_STATUS, ['AVAILABLE_NOW', 'SOON_TO_HARVEST'], true)
            && $listing->farm?->FRM_STATUS === 'APPROVED' && (bool) $listing->farm?->FRM_PIN_ACTIVE
            && $listing->farm?->farmer?->buyer?->user?->USR_STATUS === 'ACTIVE'
            && (bool) $listing->farm?->farmer?->buyer?->user?->USR_IS_SELLER;
    }

    public function listingChanged(string $id, string $event, string $eventKey): void
    {
        $listing = Listing::with('farm.farmer.buyer.user', 'category')->find($id);
        if (! $listing || ! $this->publicListing($listing)) {
            return;
        }
        if ($event === 'available' && $listing->LST_STATUS !== 'AVAILABLE_NOW') {
            return;
        }
        $owner = $listing->farm->farmer->buyer->USR_ID;
        $savedIds = DB::table('saved_farm')->where('FRM_ID', $listing->FRM_ID)->pluck('USR_ID')->all();
        $subscribers = User::where('USR_STATUS', 'ACTIVE')->where('USR_ID', '!=', $owner)
            ->where('USR_PREMIUM_EXPIRES_AT', '>', now())
            ->when($listing->LST_STATUS !== 'AVAILABLE_NOW', fn ($q) => $q->whereIn('USR_ID', $savedIds))->get();
        $crop = $listing->LST_CROP_ICON ?: $listing->category?->CAT_NAME ?: 'A crop';
        $farm = $listing->farm->FRM_NAME;
        foreach ($subscribers as $user) {
            $settings = self::settings($user->USR_ID);
            if (! $settings['enabled']) {
                continue;
            }
            $cropMatch = $listing->LST_STATUS === 'AVAILABLE_NOW' && $settings['crop_alerts']
                && in_array($this->cropKey($crop), array_map(fn ($name) => $this->cropKey($name), $settings['crops']), true);
            if ($cropMatch) {
                // A single crop alert covers the event when the farm is also saved.
                $this->deliver($user->USR_ID, 'CROP_AVAILABLE', $listing->LST_ID, $eventKey,
                    "$crop is available now", "$farm has $crop available now. Open the listing to confirm details.", $crop);

                continue;
            }
            if (! $settings['saved_farms'] || ! in_array($user->USR_ID, $savedIds, true)) {
                continue;
            }
            $type = $event === 'new' ? 'SAVED_FARM_NEW_LISTING' : 'SAVED_FARM_AVAILABLE';
            $state = $listing->LST_STATUS === 'AVAILABLE_NOW' ? 'available now' : 'soon to harvest';
            $this->deliver($user->USR_ID, $type, $listing->LST_ID, $eventKey,
                $event === 'new' ? 'New listing from a saved farm' : 'A saved farm has crops available',
                "$farm: $crop is $state. Open the listing to confirm details.", $crop);
        }
    }

    private function cropKey(string $name): string
    {
        return app(CropCatalog::class)->key($name);
    }

    public function requestCreated(string $id): void
    {
        $request = BuyRequest::with('owner')->find($id);
        if (! $request || $request->BRQ_REMOVED_AT !== null || $request->owner?->USR_STATUS !== 'ACTIVE' || ! $request->owner?->USR_IS_PREMIUM) {
            return;
        }
        // Sellers receive relevant demand alerts regardless of subscription.
        $matches = Listing::with('farm.farmer.buyer.user', 'category')->where('LST_AVAILABILITY', 'ACTIVE')->whereIn('LST_STATUS', ['AVAILABLE_NOW', 'SOON_TO_HARVEST'])->get();
        $recipients = [];
        foreach ($matches as $listing) {
            if (! $this->publicListing($listing) || $this->cropKey($listing->LST_CROP_ICON ?: $listing->category?->CAT_NAME ?: '') !== $this->cropKey($request->BRQ_CROP)) {
                continue;
            }
            $userId = $listing->farm->farmer->buyer->USR_ID;
            if ($userId === $request->USR_ID || isset($recipients[$userId])) {
                continue;
            }
            $recipients[$userId] = true;
            $settings = self::settings($userId);
            if (! $settings['enabled'] || ! $settings['buy_requests']) {
                continue;
            }
            $this->deliver($userId, 'BUY_REQUEST_MATCH', $id, 'created', 'A buyer is looking for your crop',
                "A buyer requested {$request->BRQ_QUANTITY_KG} kg of {$request->BRQ_CROP}. Open Buy Requests to view and contact them.", $request->BRQ_CROP);
        }
    }

    private function deliver(string $userId, string $type, string $ref, string $event, string $title, string $body, string $crop): void
    {
        DB::transaction(function () use ($userId, $type, $ref, $event, $title, $body, $crop) {
            $key = hash('sha256', implode('|', [$userId, $type, $ref, $event]));
            $inserted = DB::table('premium_alert_delivery')->insertOrIgnore(['DELIVERY_KEY' => $key, 'USR_ID' => $userId, 'CREATED_AT' => now()]);
            if (! $inserted) {
                return;
            }
            // The inbox remains immediate; phone delivery is grouped separately.
            app(NotificationService::class)->notify($userId, $type, Str::substr($title, 0, 100), Str::substr($body, 0, 300), $ref, false);
            app(PremiumPushService::class)->enqueue($key, $userId, $type, $ref, $crop);
        });
    }
}
