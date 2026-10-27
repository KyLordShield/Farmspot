<?php

namespace Tests\Feature;

use App\Models\AdminPlanner;
use App\Models\User;
use App\Services\EventNotificationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class EventNotificationTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.onesignal.app_id' => 'test-app', 'services.onesignal.rest_api_key' => 'test-key',
            'services.onesignal.base_url' => 'https://push.example.test']);
        Http::preventStrayRequests();
        Http::fake(['*' => Http::response(['id' => 'accepted'], 200)]);
    }

    private function admin(): User
    {
        return User::create(['USR_ID' => 'ADMIN1', 'USR_NAME' => 'Event Admin', 'USR_EMAIL' => 'admin@event.test',
            'USR_PASSWORD' => bcrypt('example123'), 'USR_MOBILE_NUMBER' => '09000000000',
            'USR_ROLE' => 'ADMIN', 'USR_STATUS' => 'ACTIVE', 'USR_IS_SELLER' => 0, 'USR_CREATED_AT' => now()]);
    }

    private function sellers(int $count): void
    {
        $users = $buyers = $farmers = $farms = [];
        for ($i = 1; $i <= $count; $i++) {
            $id = str_pad((string) $i, 5, '0', STR_PAD_LEFT);
            $users[] = ['USR_ID' => 'U'.$id, 'USR_NAME' => 'Farmer '.$id, 'USR_EMAIL' => $id.'@event.test',
                'USR_PASSWORD' => 'not-used-by-these-tests', 'USR_MOBILE_NUMBER' => '09123'.str_pad((string) $i, 6, '0', STR_PAD_LEFT),
                'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE', 'USR_IS_SELLER' => 1, 'USR_CREATED_AT' => now()->subMinute()];
            $buyers[] = ['BUY_ID' => 'B'.$id, 'USR_ID' => 'U'.$id];
            $farmers[] = ['FMR_ID' => 'R'.$id, 'BUY_ID' => 'B'.$id, 'FMR_SELLER_MODE_ACTIVE' => 1];
            $farms[] = ['FRM_ID' => 'F'.$id, 'FMR_ID' => 'R'.$id, 'FRM_NAME' => 'Farm '.$id,
                'FRM_BARANGAY' => 'Pusok', 'FRM_LATITUDE' => 10.3, 'FRM_LONGITUDE' => 123.9,
                'FRM_STATUS' => 'APPROVED', 'FRM_PIN_ACTIVE' => 1, 'FRM_CREATED_AT' => now()];
        }
        DB::table('user')->insert($users);
        DB::table('buyer')->insert($buyers);
        DB::table('farmer')->insert($farmers);
        DB::table('farm')->insert($farms);
    }

    private function event(): AdminPlanner
    {
        $admin = User::find('ADMIN1') ?? $this->admin();

        return AdminPlanner::create(['APL_ID' => 'EVENT1', 'USR_ID' => $admin->USR_ID, 'APL_TYPE' => 'EVENT',
            'APL_TITLE' => 'Farmers meeting', 'APL_BODY' => 'At the barangay hall.',
            'APL_DATETIME' => '2026-11-05 09:00:00', 'APL_NOTIFY_FARMERS' => true, 'APL_IS_DONE' => 0, 'APL_CREATED_AT' => now()]);
    }

    public function test_saving_an_event_only_queues_and_private_notes_do_not_broadcast(): void
    {
        $this->sellers(1);
        $admin = $this->admin();
        $this->actingAs($admin)->post('/planner', ['APL_TYPE' => 'EVENT', 'APL_TITLE' => 'Meeting',
            'APL_DATETIME' => '2026-11-05T09:00', 'APL_NOTIFY_FARMERS' => '1'])->assertRedirect(route('dashboard'));
        $this->assertDatabaseCount('event_notice', 1);
        $this->assertDatabaseCount('notification', 0);
        Http::assertNothingSent();
        $this->post('/planner', ['APL_TYPE' => 'NOTE', 'APL_TITLE' => 'Private', 'APL_NOTIFY_FARMERS' => '1'])->assertRedirect();
        $this->post('/planner', ['APL_TYPE' => 'EVENT', 'APL_TITLE' => 'Private event', 'APL_DATETIME' => '2026-11-05T09:00'])->assertRedirect();
        $this->assertDatabaseCount('event_notice', 1);
    }

    public function test_fanout_is_bounded_and_deduplicated_with_one_push_per_batch(): void
    {
        $this->sellers(205);
        $service = app(EventNotificationService::class);
        $event = $this->event();
        $service->enqueue($event);
        $service->enqueue($event);
        $this->assertDatabaseCount('event_notice', 1);
        $service->run(999); // Even a bad caller cannot exceed the limit.
        $this->assertDatabaseCount('notification', 200);
        Http::assertSentCount(2);
        Http::assertSent(fn ($request) => count($request['include_aliases']['external_id']) === 100
            && $request['idempotency_key'] && str_contains($request['contents']['en'], '9:00 AM'));
        $service->run();
        $service->run();
        $this->assertDatabaseCount('notification', 205);
        Http::assertSentCount(3);
        $this->assertSame(205, DB::table('notification')->distinct()->count('USR_ID'));
    }

    public function test_only_active_approved_sellers_receive_one_copy_even_with_multiple_farms(): void
    {
        $this->sellers(4);
        DB::table('user')->where('USR_ID', 'U00002')->update(['USR_STATUS' => 'DEACTIVATED']);
        DB::table('user')->where('USR_ID', 'U00003')->update(['USR_IS_SELLER' => 0]);
        DB::table('farm')->where('FRM_ID', 'F00004')->update(['FRM_STATUS' => 'PENDING_REVIEW']);
        $farm = (array) DB::table('farm')->where('FRM_ID', 'F00001')->first();
        $farm['FRM_ID'] = 'SECOND';
        DB::table('farm')->insert($farm);
        $service = app(EventNotificationService::class);
        $service->enqueue($this->event());
        $service->run();
        $this->assertDatabaseCount('notification', 1);
        $this->assertDatabaseHas('notification', ['USR_ID' => 'U00001', 'NOTIF_TYPE' => 'CALENDAR_EVENT']);
    }

    public function test_failed_push_retries_same_payload_and_key_without_duplicating_inbox(): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::preventStrayRequests();
        Http::fake(['*' => Http::sequence()->push(['error' => 'busy'], 503)->push(['id' => 'accepted'], 200)]);
        $this->sellers(1);
        $service = app(EventNotificationService::class);
        $service->enqueue($this->event());
        $service->run();
        $batch = DB::table('event_notice_batch')->first();
        $this->assertSame('pending', $batch->STATE);
        $this->assertDatabaseCount('notification', 1);
        $service->run();
        Http::assertSentCount(1);
        $this->travel(3)->minutes();
        $service->run();
        $this->travelBack();
        Http::assertSentCount(2);
        $sent = Http::recorded();
        $this->assertSame($sent[0][0]['idempotency_key'], $sent[1][0]['idempotency_key']);
        $this->assertSame($sent[0][0]->data(), $sent[1][0]->data());
        $this->assertDatabaseCount('notification', 1);
        $this->assertSame('sent', DB::table('event_notice_batch')->first()->STATE);
    }

    public function test_missing_push_configuration_still_delivers_inbox_and_does_not_block_next_batch(): void
    {
        config(['services.onesignal.rest_api_key' => null]);
        $this->sellers(1);
        $service = app(EventNotificationService::class);
        $service->enqueue($this->event());
        $service->run();
        $this->assertDatabaseCount('notification', 1);
        $this->assertSame('inbox_only', DB::table('event_notice_batch')->first()->STATE);
        Http::assertNothingSent();
    }

    public function test_deleted_event_cancels_unstarted_delivery_and_foreign_admin_cannot_delete_it(): void
    {
        $this->sellers(1);
        $event = $this->event();
        app(EventNotificationService::class)->enqueue($event);
        $other = User::create(['USR_ID' => 'ADMIN2', 'USR_NAME' => 'Other Admin', 'USR_EMAIL' => 'other@event.test',
            'USR_PASSWORD' => bcrypt('example123'), 'USR_MOBILE_NUMBER' => '09000000002', 'USR_ROLE' => 'ADMIN',
            'USR_STATUS' => 'ACTIVE', 'USR_CREATED_AT' => now()]);
        $this->actingAs($other)->delete('/planner/EVENT1')->assertNotFound();
        $this->actingAs(User::find('ADMIN1'))->delete('/planner/EVENT1')->assertRedirect();
        app(EventNotificationService::class)->run();
        $this->assertDatabaseCount('notification', 0);
        Http::assertNothingSent();
    }
    public function test_crashed_worker_lease_recovers_with_no_duplicate_inbox_rows(): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory);
        Http::fake(['*' => Http::sequence()->push(['error' => 'busy'], 503)->push(['id' => 'accepted'], 200)]);
        $this->sellers(1);
        $service = app(EventNotificationService::class);
        $service->enqueue($this->event());
        $service->run();
        DB::table('event_notice_batch')->update(['LEASE_UNTIL' => now()->addMinute(), 'NEXT_AT' => now()]);
        $service->run();
        Http::assertSentCount(1);
        $this->travel(2)->minutes();
        $service->run();
        $this->travelBack();
        Http::assertSentCount(2);
        $this->assertDatabaseCount('notification', 1);
        $this->assertSame('sent', DB::table('event_notice_batch')->first()->STATE);
    }

    public function test_long_details_fit_the_inbox_and_edits_do_not_repeat_the_announcement(): void
    {
        $this->sellers(1);
        $event = $this->event();
        $event->update(['APL_BODY' => str_repeat('Meeting details ', 100)]);
        $service = app(EventNotificationService::class);
        $service->enqueue($event);
        $service->run();
        $notice = DB::table('notification')->first();
        $this->assertLessThanOrEqual(300, mb_strlen($notice->NOTIF_BODY));
        $this->assertStringContainsString('9:00 AM', $notice->NOTIF_BODY);
        $this->actingAs(User::find('ADMIN1'))->put('/planner/EVENT1', ['APL_TITLE' => 'Updated title',
            'APL_BODY' => 'Updated details', 'APL_DATETIME' => '2026-11-05T09:00'])->assertRedirect();
        $service->run();
        $this->assertDatabaseCount('notification', 1);
        Http::assertSentCount(1);
    }

}
