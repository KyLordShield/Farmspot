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
use App\Services\PremiumAlertService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CropAlertsTest extends TestCase
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

    private function watch(User $user, array $crops, array $extra = []): void
    {
        Sanctum::actingAs($user);
        $this->putJson('/api/premium/alert-settings', array_merge(['enabled' => true, 'saved_farms' => false, 'buy_requests' => true, 'crop_alerts' => true, 'crops' => $crops], $extra))->assertOk();
    }

    public function test_crop_selection_persists_with_alias_catalog_and_remains_account_scoped(): void
    {
        $first = $this->account(true);
        $second = $this->account(true);
        $this->watch($first, ['Cabbage', 'Tomato'], ['USR_ID' => $second->USR_ID]);
        $this->getJson('/api/premium/alert-settings')->assertJsonPath('crops', ['Cabbage', 'Tomato'])->assertJsonPath('crop_aliases.Tomato', ['kamatis']);
        // Older clients changing other preferences must not erase crop choices.
        $this->putJson('/api/premium/alert-settings', ['enabled' => false, 'saved_farms' => false, 'buy_requests' => true])->assertOk()->assertJsonPath('crops', ['Cabbage', 'Tomato']);
        Sanctum::actingAs($second);
        $this->getJson('/api/premium/alert-settings')->assertJsonPath('crops', []);
        $this->putJson('/api/premium/alert-settings', ['enabled' => true, 'saved_farms' => false, 'buy_requests' => true, 'crops' => ['unknown crop']])->assertUnprocessable();
        $this->watch($first, []);
        $this->getJson('/api/premium/alert-settings')->assertJsonPath('crops', []);
    }

    public function test_unsaved_farms_notify_for_available_aliases_and_harvest_transitions(): void
    {
        $user = $this->account(true);
        $this->watch($user, ['Tomato']);
        $near = $this->farm();
        $far = $this->farm();
        $far->update(['FRM_LATITUDE' => 17, 'FRM_LONGITUDE' => 120]);
        $now = $this->listing($near, 'Kamatis');
        $soon = $this->listing($far, 'Tomato', 'SOON_TO_HARVEST');
        $this->assertSame(1, UserNotification::where('USR_ID', $user->USR_ID)->count());
        $this->assertDatabaseHas('notification', ['USR_ID' => $user->USR_ID, 'NOTIF_TYPE' => 'CROP_AVAILABLE', 'NOTIF_REF_ID' => $now->LST_ID]);
        $soon->update(['LST_STATUS' => 'AVAILABLE_NOW']);
        $this->assertSame(2, UserNotification::where('USR_ID', $user->USR_ID)->count());
        $this->assertDatabaseHas('notification', ['USR_ID' => $user->USR_ID, 'NOTIF_TYPE' => 'CROP_AVAILABLE', 'NOTIF_REF_ID' => $soon->LST_ID]);
        $this->assertSame(0, DB::table('saved_farm')->where('USR_ID', $user->USR_ID)->count());
    }

    public function test_crop_delivery_respects_switches_expiry_and_visible_matching_listings(): void
    {
        $farm = $this->farm();
        $paused = $this->account(true);
        $off = $this->account(true);
        $expired = $this->account(true);
        $active = $this->account(true);
        $this->watch($paused, ['Tomato'], ['enabled' => false]);
        $this->watch($off, ['Tomato'], ['crop_alerts' => false]);
        $this->watch($expired, ['Tomato']);
        $expired->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->subDay()])->save();
        $this->watch($active, ['Cabbage']);
        $owner = $farm->farmer->buyer->user;
        $owner->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->addMonth()])->save();
        $this->watch($owner, ['Tomato']);
        $this->listing($farm, 'Tomato');
        $this->listing($farm, 'Cabbage', 'NOT_AVAILABLE');
        $this->listing($farm, 'Cabbage', 'AVAILABLE_NOW', 'REMOVED');
        $farm->update(['FRM_STATUS' => 'ARCHIVED']);
        $this->listing($farm, 'Cabbage');
        $this->assertSame(0, UserNotification::where('NOTIF_TYPE', 'CROP_AVAILABLE')->count());
        Sanctum::actingAs($expired->fresh());
        $this->putJson('/api/premium/alert-settings', ['enabled' => true, 'saved_farms' => false, 'buy_requests' => true, 'crops' => ['Tomato', 'Cabbage']])->assertForbidden();
        $this->watch($expired->fresh(), []);
        Sanctum::actingAs($this->account());
        $this->putJson('/api/premium/alert-settings', ['enabled' => true, 'saved_farms' => false, 'buy_requests' => true, 'crops' => ['Tomato']])->assertForbidden();
    }

    public function test_saved_farm_overlap_and_routine_edits_do_not_duplicate_crop_alerts(): void
    {
        $farm = $this->farm();
        $user = $this->account(true);
        $this->follow($user, $farm);
        $this->watch($user, ['Tomato'], ['saved_farms' => true]);
        $listing = $this->listing($farm, 'Kamatis');
        app(PremiumAlertService::class)->listingChanged($listing->LST_ID, 'new', 'created');
        $listing->update(['LST_DESCRIPTION' => 'Edited description']);
        $this->assertSame(1, UserNotification::where('USR_ID', $user->USR_ID)->count());
        $this->assertDatabaseHas('notification', ['USR_ID' => $user->USR_ID, 'NOTIF_TYPE' => 'CROP_AVAILABLE']);
    }

    public function test_saved_custom_crop_remains_valid_after_stock_disappears(): void
    {
        $farm = $this->farm();
        $listing = $this->listing($farm, 'Local Purple Greens');
        $user = $this->account(true);
        $this->watch($user, ['Local Purple Greens']);
        $listing->update(['LST_STATUS' => 'NOT_AVAILABLE']);
        $this->watch($user, ['Local Purple Greens']);
        $this->getJson('/api/premium/alert-settings')->assertJsonPath('crops',['Local Purple Greens']);
        $listing->update(['LST_STATUS' => 'AVAILABLE_NOW']);
        $this->assertDatabaseHas('notification',['USR_ID' => $user->USR_ID, 'NOTIF_TYPE' => 'CROP_AVAILABLE']);
    }
}
