<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\BuyRequest;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\User;
use App\Models\UserNotification;
use App\Services\NotificationService;
use App\Services\PremiumAlertService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PremiumAlertsTest extends TestCase
{
    use RefreshDatabase;

    private function account(bool $premium = false): User
    {
        $id = strtoupper(Str::random(6));
        $user = User::create(['USR_ID' => $id, 'USR_NAME' => 'Save Test', 'USR_EMAIL' => strtolower($id).'@saved.test', 'USR_PASSWORD' => bcrypt('password123'), 'USR_MOBILE_NUMBER' => '09'.random_int(1000000000, 9999999999), 'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE', 'USR_IS_SELLER' => 0, 'USR_CREATED_AT' => now()]);
        if ($premium) {
            $user->USR_PREMIUM_EXPIRES_AT = now()->addMonth();
            $user->save();
        }

        return $user;
    }

    private function farm(): Farm
    {
        $owner = $this->account();
        $owner->USR_IS_SELLER = 1;
        $owner->save();
        $buyer = Buyer::create(['BUY_ID' => strtoupper(Str::random(6)), 'USR_ID' => $owner->USR_ID]);
        $farmer = Farmer::create(['FMR_ID' => strtoupper(Str::random(6)), 'BUY_ID' => $buyer->BUY_ID, 'FMR_SELLER_MODE_ACTIVE' => 1]);

        return Farm::create(['FRM_ID' => strtoupper(Str::random(6)), 'FMR_ID' => $farmer->FMR_ID, 'FRM_NAME' => 'Saved Test Farm', 'FRM_BARANGAY' => 'Sudlon', 'FRM_LATITUDE' => 10.3, 'FRM_LONGITUDE' => 123.9, 'FRM_STATUS' => 'APPROVED', 'FRM_PIN_ACTIVE' => 1, 'FRM_CREATED_AT' => now()]);
    }

    private function listing(Farm $farm, string $crop, string $status = 'AVAILABLE_NOW', string $availability = 'ACTIVE'): Listing
    {
        $category = CropCategory::first() ?? CropCategory::create(['CAT_ID' => strtoupper(Str::random(6)), 'CAT_NAME' => 'Vegetables']);

        return Listing::create(['LST_ID' => strtoupper(Str::random(6)), 'FMR_ID' => $farm->FMR_ID, 'FRM_ID' => $farm->FRM_ID, 'CAT_ID' => $category->CAT_ID, 'LST_CROP_ICON' => $crop, 'LST_STATUS' => $status, 'LST_AVAILABILITY' => $availability, 'LST_CREATED_AT' => now(), 'LST_UPDATED_AT' => now()]);
    }

    private function follow(User $user, Farm $farm): void
    {
        DB::table('saved_farm')->insert(['USR_ID' => $user->USR_ID, 'FRM_ID' => $farm->FRM_ID, 'SAVED_AT' => now()]);
    }

    private function settings(User $user, array $extra = []): void
    {
        DB::table('premium_alert_setting')->upsert([array_merge(['USR_ID' => $user->USR_ID, 'ALERTS_ENABLED' => true, 'SAVED_FARM_ALERTS' => true, 'BUY_REQUEST_ALERTS' => true], $extra)], ['USR_ID']);
    }

    private function request(User $buyer, string $crop = 'Tomato'): BuyRequest
    {
        return BuyRequest::create(['BRQ_ID' => strtoupper(Str::random(6)), 'USR_ID' => $buyer->USR_ID, 'BRQ_CROP' => $crop, 'BRQ_QUANTITY_KG' => 20, 'BRQ_FREQUENCY' => 'weekly', 'BRQ_CREATED_AT' => now()]);
    }

    public function test_settings_are_private_persistent_and_available_to_free_sellers(): void
    {
        $this->getJson('/api/premium/alert-settings')->assertUnauthorized();
        $first = $this->account();
        $second = $this->account();
        Sanctum::actingAs($first);
        $this->getJson('/api/premium/alert-settings')->assertOk()->assertJsonPath('enabled', true);
        $this->putJson('/api/premium/alert-settings', ['enabled' => false, 'saved_farms' => true, 'buy_requests' => false, 'USR_ID' => $second->USR_ID])->assertOk()->assertJsonPath('buy_requests', false);
        $this->getJson('/api/premium/alert-settings')->assertJsonPath('enabled', false);
        Sanctum::actingAs($second);
        $this->getJson('/api/premium/alert-settings')->assertJsonPath('enabled', true)->assertJsonPath('buy_requests', true);
        $this->putJson('/api/premium/alert-settings', ['enabled' => 'bad'])->assertUnprocessable();
    }

    public function test_saved_farm_new_and_available_events_are_delivered_once_and_edits_are_quiet(): void
    {
        $farm = $this->farm();
        $subscriber = $this->account(true);
        $this->follow($subscriber, $farm);
        $listing = $this->listing($farm, 'Tomato', 'SOON_TO_HARVEST');
        $this->assertDatabaseHas('notification', ['USR_ID' => $subscriber->USR_ID, 'NOTIF_TYPE' => 'SAVED_FARM_NEW_LISTING', 'NOTIF_REF_ID' => $listing->LST_ID]);
        app(PremiumAlertService::class)->listingChanged($listing->LST_ID, 'new', 'created');
        $this->assertSame(1, UserNotification::where('USR_ID', $subscriber->USR_ID)->count());
        $listing->update(['LST_DESCRIPTION' => 'New description']);
        $this->assertSame(1, UserNotification::where('USR_ID', $subscriber->USR_ID)->count());
        DB::transaction(fn () => $listing->update(['LST_STATUS' => 'AVAILABLE_NOW', 'LST_EXPIRY_DATE' => now()->addDays(3)]));
        $this->assertSame(2, UserNotification::where('USR_ID', $subscriber->USR_ID)->count());
        $this->assertDatabaseHas('notification', ['USR_ID' => $subscriber->USR_ID, 'NOTIF_TYPE' => 'SAVED_FARM_AVAILABLE']);
        $listing->update(['LST_STATUS' => 'AVAILABLE_NOW']);
        $this->assertSame(2, UserNotification::where('USR_ID', $subscriber->USR_ID)->count());
    }

    public function test_saved_farm_alerts_respect_premium_preferences_visibility_and_self_exclusion(): void
    {
        $farm = $this->farm();
        $free = $this->account();
        $expired = $this->account(true);
        $muted = $this->account(true);
        $paused = $this->account(true);
        $inactive = $this->account(true);
        $expired->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->subDay()])->save();
        $inactive->update(['USR_STATUS' => 'DEACTIVATED']);
        $this->settings($muted, ['SAVED_FARM_ALERTS' => false]);
        $this->settings($paused, ['ALERTS_ENABLED' => false]);
        foreach ([$free, $expired, $muted, $paused, $inactive] as $u) {
            $this->follow($u, $farm);
        }
        $owner = $farm->farmer->buyer->user;
        $owner->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->addMonth()])->save();
        $this->follow($owner, $farm);
        $this->listing($farm, 'Tomato');
        $this->assertSame(0, UserNotification::whereIn('NOTIF_TYPE', ['SAVED_FARM_NEW_LISTING', 'SAVED_FARM_AVAILABLE'])->count());
        $active = $this->account(true);
        $this->follow($active, $farm);
        $this->listing($farm, 'Cabbage', 'AVAILABLE_NOW', 'REMOVED');
        $this->listing($farm, 'Cabbage', 'NOT_AVAILABLE');
        $farm->update(['FRM_STATUS' => 'ARCHIVED']);
        $this->listing($farm, 'Cabbage');
        $this->assertSame(0, UserNotification::where('USR_ID', $active->USR_ID)->count());
    }

    public function test_requests_match_aliases_and_deduplicate_multiple_listings_for_free_sellers(): void
    {
        $farm = $this->farm();
        $seller = $farm->farmer->buyer->user;
        $this->listing($farm, 'Kamatis');
        $this->listing($farm, 'Tomato', 'SOON_TO_HARVEST');
        $other = $this->farm();
        $this->listing($other, 'Tomato', 'NOT_AVAILABLE');
        $removed = $this->farm();
        $this->listing($removed, 'Tomato', 'AVAILABLE_NOW', 'REMOVED');
        $request = $this->request($this->account(true));
        app(PremiumAlertService::class)->requestCreated($request->BRQ_ID);
        $this->assertSame(1, UserNotification::where('NOTIF_TYPE', 'BUY_REQUEST_MATCH')->count());
        $this->assertDatabaseHas('notification', ['USR_ID' => $seller->USR_ID, 'NOTIF_TYPE' => 'BUY_REQUEST_MATCH', 'NOTIF_REF_ID' => $request->BRQ_ID]);
        $this->settings($seller, ['BUY_REQUEST_ALERTS' => false]);
        $this->request($this->account(true));
        $this->assertSame(1, UserNotification::where('NOTIF_TYPE', 'BUY_REQUEST_MATCH')->count());
    }

    public function test_rolled_back_listings_do_not_generate_alerts(): void
    {
        $farm = $this->farm();
        $user = $this->account(true);
        $this->follow($user, $farm);
        try {
            DB::transaction(function () use ($farm) {
                $this->listing($farm, 'Tomato');
                throw new \RuntimeException('rollback');
            });
        } catch (\RuntimeException $e) {
            $this->assertSame('rollback', $e->getMessage());
        }
        $this->assertSame(0, UserNotification::where('USR_ID', $user->USR_ID)->count());
        $this->assertSame(0, DB::table('premium_alert_delivery')->count());
    }

    public function test_harvest_command_alerts_saved_farm_subscribers(): void
    {
        config(['services.onesignal.app_id' => null, 'services.onesignal.rest_api_key' => null]);
        $farm = $this->farm();
        $user = $this->account(true);
        $this->follow($user, $farm);
        $listing = $this->listing($farm, 'Tomato', 'SOON_TO_HARVEST');
        $listing->update(['LST_HARVEST_DATE' => now('Asia/Manila')->toDateString()]);
        $this->artisan('listings:harvest')->assertSuccessful();
        $this->assertDatabaseHas('notification', ['USR_ID' => $user->USR_ID, 'NOTIF_TYPE' => 'SAVED_FARM_AVAILABLE', 'NOTIF_REF_ID' => $listing->LST_ID]);
        $this->artisan('listings:harvest')->assertSuccessful();
        $this->assertSame(1, UserNotification::where('USR_ID', $user->USR_ID)->where('NOTIF_TYPE', 'SAVED_FARM_AVAILABLE')->count());
    }

    public function test_notification_failure_does_not_break_listing_and_delivery_can_retry(): void
    {
        $farm = $this->farm();
        $user = $this->account(true);
        $this->follow($user, $farm);
        $this->mock(NotificationService::class, function ($mock) {
            $mock->shouldReceive('notify')->once()->andThrow(new \RuntimeException('Inbox unavailable'));
        });
        $listing = $this->listing($farm, 'Tomato');
        $this->assertDatabaseHas('listing', ['LST_ID' => $listing->LST_ID]);
        $this->assertSame(0, DB::table('premium_alert_delivery')->count());
        app()->instance(NotificationService::class, new NotificationService);
        app(PremiumAlertService::class)->listingChanged($listing->LST_ID, 'new', 'created');
        $this->assertDatabaseHas('notification', ['USR_ID' => $user->USR_ID, 'NOTIF_REF_ID' => $listing->LST_ID]);
    }
}
