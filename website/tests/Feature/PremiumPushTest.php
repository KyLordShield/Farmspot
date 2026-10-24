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
use App\Services\PremiumPushService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Factory;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PremiumPushTest extends TestCase
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

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(Carbon::parse('2026-10-25 01:00:00', 'UTC'));
        config(['services.onesignal.app_id' => 'test-app', 'services.onesignal.rest_api_key' => 'test-key', 'services.onesignal.base_url' => 'https://push.test']);
        Http::preventStrayRequests();
        Http::fake(['https://push.test/*' => Http::response(['id' => 'accepted-id'], 200)]);
    }

    private function subscriber(string $mode = 'hourly', array $extra = []): User
    {
        $user = $this->account(true);
        $this->settings($user, array_merge(['PUSH_ENABLED' => true, 'PUSH_FREQUENCY' => $mode, 'QUIET_ENABLED' => false, 'CROP_ALERTS' => true, 'ALERT_CROPS' => json_encode(['Tomato'])], $extra));

        return $user;
    }

    public function test_push_is_opt_in_and_inbox_is_immediate(): void
    {
        $user = $this->account(true);
        $this->watch($user, ['Tomato']);
        $this->listing($this->farm(), 'Tomato');
        $this->assertDatabaseHas('notification', ['USR_ID' => $user->USR_ID, 'NOTIF_TYPE' => 'CROP_AVAILABLE']);
        $this->assertSame(0, DB::table('premium_push_event')->count());
        $this->assertSame(0, app(PremiumPushService::class)->flush());
        Http::assertNothingSent();
    }

    public function test_hourly_summary_groups_farms_and_enforces_hourly_spacing(): void
    {
        $user = $this->subscriber();
        $farm = $this->farm();
        $this->listing($farm, 'Tomato');
        $this->listing($this->farm(), 'Kamatis');
        $push = app(PremiumPushService::class);
        $this->assertSame(0, $push->flush());
        $this->travel(61)->minutes();
        $this->assertSame(1, $push->flush());
        Http::assertSent(fn ($r) => str_contains($r['contents']['en'], '2 farms') && $r['include_aliases']['external_id'] === [$user->USR_ID]);
        $this->listing($farm, 'Tomato');
        $this->travel(59)->minutes();
        $this->assertSame(0, $push->flush());
        $this->travel(2)->minutes();
        $this->assertSame(1, $push->flush());
        Http::assertSentCount(2);
    }

    public function test_instant_is_still_one_push_per_crop_per_hour_and_overlap_is_single(): void
    {
        $user = $this->subscriber('instant');
        $farm = $this->farm();
        $this->follow($user, $farm);
        $this->listing($farm, 'Tomato');
        $this->listing($this->farm(), 'Kamatis');
        $push = app(PremiumPushService::class);
        $this->assertSame(1, $push->flush());
        $this->listing($farm, 'Tomato');
        $this->assertSame(0, $push->flush());
        $this->travel(61)->minutes();
        $this->assertSame(1, $push->flush());
        Http::assertSentCount(2);
        $this->assertSame(3, DB::table('premium_push_event')->count());
    }

    public function test_daily_digest_waits_through_overnight_quiet_hours_and_sends_once(): void
    {
        $this->travelTo(Carbon::parse('2026-10-25 21:30:00', 'Asia/Manila'));
        $user = $this->subscriber('daily', ['QUIET_ENABLED' => true, 'QUIET_START' => '22:00', 'QUIET_END' => '07:00', 'DAILY_TIME' => '06:30']);
        $farm = $this->farm();
        $this->listing($farm, 'Tomato');
        $push = app(PremiumPushService::class);
        $this->travelTo(Carbon::parse('2026-10-25 23:00:00', 'Asia/Manila'));
        $this->assertSame(0, $push->flush());
        $this->travelTo(Carbon::parse('2026-10-26 06:45:00', 'Asia/Manila'));
        $this->assertSame(0, $push->flush());
        $this->travelTo(Carbon::parse('2026-10-26 07:00:00', 'Asia/Manila'));
        $this->assertSame(1, $push->flush());
        $this->listing($farm, 'Tomato');
        $this->assertSame(0, $push->flush());
        Http::assertSentCount(1);
    }

    public function test_expiry_and_push_opt_out_cancel_pending_phone_alerts_without_removing_inbox(): void
    {
        $user = $this->subscriber();
        $this->listing($this->farm(), 'Tomato');
        $user->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->subMinute()])->save();
        $this->travel(61)->minutes();
        $this->assertSame(0, app(PremiumPushService::class)->flush());
        $this->assertSame(1, UserNotification::where('USR_ID', $user->USR_ID)->count());
        $other = $this->subscriber();
        $this->listing($this->farm(), 'Tomato');
        Sanctum::actingAs($other);
        $this->putJson('/api/premium/alert-settings', ['enabled' => true, 'saved_farms' => true, 'buy_requests' => true, 'push_enabled' => false])->assertOk();
        $this->assertSame(0, DB::table('premium_push_event')->where('USR_ID', $other->USR_ID)->whereNull('HANDLED_AT')->count());
        $this->travel(61)->minutes();
        $this->assertSame(0, app(PremiumPushService::class)->flush());
        Http::assertNothingSent();
    }

    public function test_failed_provider_retries_reuse_same_batch_and_idempotency_key(): void
    {
        $user = $this->subscriber('instant');
        $this->listing($this->farm(), 'Tomato');
        Http::swap(new Factory);
        Http::preventStrayRequests();
        Http::fake(['https://push.test/*' => Http::sequence()->push(['error' => 'temporary'], 503)->push(['id' => 'sent-on-retry'], 200)]);
        $push = app(PremiumPushService::class);
        $this->assertSame(0, $push->flush());
        $id = DB::table('premium_push_batch')->value('ID');
        $this->assertSame(1, DB::table('premium_push_event')->whereNull('HANDLED_AT')->count());
        $this->travel(5)->minutes();
        $this->assertSame(1, $push->flush());
        $this->assertSame(1, DB::table('premium_push_batch')->count());
        Http::assertSent(fn ($r) => $r['idempotency_key'] === $id);
        Http::assertSentCount(2);
    }

    public function test_removed_stock_is_not_pushed_and_settings_validate_quiet_hours(): void
    {
        $user = $this->subscriber();
        $listing = $this->listing($this->farm(), 'Tomato');
        $listing->update(['LST_STATUS' => 'NOT_AVAILABLE']);
        $this->travel(61)->minutes();
        $this->assertSame(0, app(PremiumPushService::class)->flush());
        Http::assertNothingSent();
        Sanctum::actingAs($user);
        $this->putJson('/api/premium/alert-settings', ['enabled' => true, 'saved_farms' => true, 'buy_requests' => true, 'push_enabled' => true, 'push_frequency' => 'daily', 'quiet_enabled' => true, 'quiet_start' => '22:00', 'quiet_end' => '22:00'])->assertUnprocessable();
        $this->putJson('/api/premium/alert-settings', ['enabled' => true, 'saved_farms' => true, 'buy_requests' => true, 'push_frequency' => 'spam'])->assertUnprocessable();
    }

    public function test_provider_acceptance_without_a_recipient_is_not_recorded_as_sent(): void
    {
        $user = $this->subscriber('instant');
        $this->listing($this->farm(), 'Tomato');
        Http::swap(new Factory);
        Http::preventStrayRequests();
        Http::fake(['https://push.test/*' => Http::response(['id' => '', 'errors' => ['No subscribed users']], 200)]);
        $this->assertSame(0, app(PremiumPushService::class)->flush());
        $this->assertSame(0, DB::table('premium_push_batch')->whereNotNull('SENT_AT')->count());
        $this->assertSame(1, DB::table('premium_push_batch')->value('ATTEMPTS'));
    }

    public function test_free_seller_receives_matching_request_push_but_removed_request_is_skipped(): void
    {
        $farm = $this->farm();
        $seller = $farm->farmer->buyer->user;
        $this->settings($seller, ['PUSH_ENABLED' => true, 'PUSH_FREQUENCY' => 'instant', 'QUIET_ENABLED' => false]);
        $this->listing($farm, 'Kamatis');
        $request = $this->request($this->account(true));
        $push = app(PremiumPushService::class);
        $this->assertSame(1, $push->flush());
        Http::assertSent(fn ($r) => str_contains($r['contents']['en'], 'matching buy request'));
        $removed = $this->request($this->account(true));
        $removed->update(['BRQ_REMOVED_AT' => now()]);
        $this->travel(61)->minutes();
        $this->assertSame(0, $push->flush());
        Http::assertSentCount(1);
    }
}
