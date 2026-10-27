<?php

namespace Tests\Feature;

use App\Jobs\SendBuyRequestUpdate;
use App\Models\Buyer;
use App\Models\BuyRequest;
use App\Models\Conversation;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\User;
use App\Models\UserNotification;
use App\Services\EventPushSender;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class BuyRequestTest extends TestCase
{
    use RefreshDatabase;

    private function user(bool $premium = false): User
    {
        $id = strtoupper(Str::random(6));
        $user = User::create(['USR_ID' => $id, 'USR_NAME' => 'Buyer '.$id, 'USR_EMAIL' => strtolower($id).'@request.test', 'USR_PASSWORD' => bcrypt('password123'), 'USR_MOBILE_NUMBER' => '09'.random_int(1000000000, 9999999999), 'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE', 'USR_IS_SELLER' => 0, 'USR_CREATED_AT' => now()]);
        if ($premium) {
            $user->USR_PREMIUM_EXPIRES_AT = now()->addMonth();
            $user->save();
        }

        return $user;
    }

    private function seller(bool $approved = true): User
    {
        $user = $this->user();
        $user->USR_IS_SELLER = 1;
        $user->save();
        $buyer = Buyer::create(['BUY_ID' => strtoupper(Str::random(6)), 'USR_ID' => $user->USR_ID]);
        $farmer = Farmer::create(['FMR_ID' => strtoupper(Str::random(6)), 'BUY_ID' => $buyer->BUY_ID, 'FMR_SELLER_MODE_ACTIVE' => 1]);
        Farm::create(['FRM_ID' => strtoupper(Str::random(6)), 'FMR_ID' => $farmer->FMR_ID, 'FRM_NAME' => 'Request Test Farm', 'FRM_BARANGAY' => 'Sudlon', 'FRM_LATITUDE' => 10.3, 'FRM_LONGITUDE' => 123.9, 'FRM_STATUS' => $approved ? 'APPROVED' : 'PENDING_REVIEW', 'FRM_PIN_ACTIVE' => 1, 'FRM_CREATED_AT' => now()]);

        return $user;
    }

    private function postRequest(User $user, array $extra = []): string
    {
        Sanctum::actingAs($user);

        return $this->postJson('/api/buy-requests', array_merge(['crop' => 'Pechay', 'quantity_kg' => 15.5, 'frequency' => 'weekly', 'note' => 'Morning pickup preferred'], $extra))
            ->assertCreated()->assertJsonPath('request.quantity_kg', 15.5)->json('request.id');
    }

    public function test_buyer_badge_uses_current_server_premium_and_expires_without_deleting_request(): void
    {
        $owner = $this->user(true);
        $id = $this->postRequest($owner, ['is_premium' => true]);
        $seller = $this->seller();
        Sanctum::actingAs($seller);
        $this->getJson('/api/buy-requests')->assertOk()->assertJsonPath('requests.0.buyer.is_premium', true);
        $owner->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->subMinute()])->save();
        $this->getJson('/api/buy-requests')->assertOk()->assertJsonCount(0, 'requests');
        $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertNotFound();
        Sanctum::actingAs($owner->fresh());
        $this->getJson('/api/buy-requests/mine')->assertOk()->assertJsonPath('requests.0.id', $id);
        $owner->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->addMonth()])->save();
        Sanctum::actingAs($seller);
        $this->getJson('/api/buy-requests')->assertOk()->assertJsonPath('requests.0.id', $id)->assertJsonPath('requests.0.buyer.is_premium', true);
    }

    public function test_only_premium_accounts_can_post_but_requests_have_no_expiry(): void
    {
        Sanctum::actingAs($this->user());
        $this->postJson('/api/buy-requests', ['crop' => 'Pechay', 'quantity_kg' => 15, 'frequency' => 'weekly'])->assertForbidden();
        $owner = $this->user(true);
        $id = $this->postRequest($owner, ['USR_ID' => 'WRONG1', 'status' => 'closed', 'expires_at' => '2020-01-01']);
        $this->assertSame($owner->USR_ID, BuyRequest::find($id)->USR_ID);
        $this->getJson('/api/buy-requests/mine')->assertOk()->assertJsonCount(1, 'requests');
        $this->travel(40)->days();
        Sanctum::actingAs($owner->fresh());
        $this->getJson('/api/buy-requests/mine')->assertOk()->assertJsonCount(1, 'requests');
        Sanctum::actingAs($this->seller());
        $this->getJson('/api/buy-requests')->assertOk()->assertJsonCount(0, 'requests');
        Sanctum::actingAs($owner->fresh());
        $this->deleteJson('/api/buy-requests/'.$id)->assertOk();
        $this->travelBack();
    }

    public function test_expiry_preserves_existing_conversations_and_blocks_new_contacts(): void
    {
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        $seller = $this->seller();
        Sanctum::actingAs($seller);
        $thread = $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertCreated()->json('conversation.id');
        $owner->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->subMinute()])->save();
        $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertOk()->assertJsonPath('conversation.id', $thread);
        $this->postJson('/api/conversations/'.$thread.'/messages', ['content' => 'Following up after subscription expiry'])->assertCreated();
        Sanctum::actingAs($this->seller());
        $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertNotFound();
        Sanctum::actingAs($owner->fresh());
        $this->getJson('/api/buy-requests/'.$id.'/conversations')->assertOk()->assertJsonPath('conversations.0.id', $thread);
        $this->postJson('/api/conversations/'.$thread.'/messages', ['content' => 'Our discussion can continue'])->assertCreated();
    }

    public function test_free_seller_can_open_the_existing_chat_and_both_sides_can_message(): void
    {
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        $seller = $this->seller();
        Sanctum::actingAs($seller);
        $thread = $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertCreated()
            ->assertJsonPath('conversation.my_role', 'SELLER')->assertJsonPath('conversation.other_party.id', $owner->USR_ID)->json('conversation.id');
        $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertOk()->assertJsonPath('conversation.id', $thread);
        $this->assertSame(1, Conversation::where('BRQ_ID', $id)->count());
        $this->postJson('/api/conversations/'.$thread.'/messages', ['content' => 'I can supply your pechay.'])->assertCreated();
        Sanctum::actingAs($owner->fresh());
        $this->getJson('/api/conversations')->assertOk()->assertJsonPath('conversations.0.buy_request.id', $id)->assertJsonPath('conversations.0.other_party.id', $seller->USR_ID)->assertJsonPath('conversations.0.unread_count', 1);
        $this->getJson('/api/buy-requests/'.$id.'/conversations')->assertOk()->assertJsonPath('conversations.0.id', $thread);
        $this->getJson('/api/conversations/'.$thread.'/messages')->assertOk()->assertJsonPath('messages.0.content', 'I can supply your pechay.');
        $this->postJson('/api/conversations/'.$thread.'/messages', ['content' => 'What is your price?'])->assertCreated();
        Sanctum::actingAs($this->user());
        $this->getJson('/api/conversations/'.$thread.'/messages')->assertForbidden();
        $this->postJson('/api/conversations/'.$thread.'/messages', ['content' => 'Not my thread'])->assertForbidden();
    }

    public function test_removed_request_disappears_but_existing_chat_is_preserved(): void
    {
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        $seller = $this->seller();
        Sanctum::actingAs($seller);
        $thread = $this->postJson('/api/buy-requests/'.$id.'/conversation')->json('conversation.id');
        Sanctum::actingAs($owner->fresh());
        $this->deleteJson('/api/buy-requests/'.$id)->assertOk();
        $this->getJson('/api/buy-requests/mine')->assertJsonCount(0, 'requests');
        Sanctum::actingAs($seller);
        $this->getJson('/api/buy-requests')->assertJsonCount(0, 'requests');
        $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertNotFound();
        $this->postJson('/api/conversations/'.$thread.'/messages', ['content' => 'Following up our discussion'])->assertCreated();
        $this->getJson('/api/conversations/'.$thread.'/messages')->assertOk()->assertJsonPath('conversation.buy_request.removed', true);
    }

    public function test_board_includes_far_and_unknown_locations_sorted_nearest_first(): void
    {
        $far = $this->postRequest($this->user(true), ['latitude' => 15, 'longitude' => 120]);
        $unknown = $this->postRequest($this->user(true));
        $near = $this->postRequest($this->user(true), ['latitude' => 10.3, 'longitude' => 123.9]);
        Sanctum::actingAs($this->seller());
        $this->getJson('/api/buy-requests')->assertOk()->assertJsonCount(3, 'requests')
            ->assertJsonPath('requests.0.id', $near)->assertJsonPath('requests.1.id', $far)->assertJsonPath('requests.2.id', $unknown)->assertJsonPath('requests.2.distance_km', null)->assertJsonMissingPath('requests.0.latitude');
        $this->getJson('/api/buy-requests?search=Tomato')->assertJsonCount(0, 'requests');
    }

    public function test_nonowners_and_unapproved_sellers_cannot_access_requests(): void
    {
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        Sanctum::actingAs($this->user());
        $this->getJson('/api/buy-requests')->assertForbidden();
        $this->deleteJson('/api/buy-requests/'.$id)->assertForbidden();
        $this->getJson('/api/buy-requests/'.$id.'/conversations')->assertForbidden();
        Sanctum::actingAs($this->seller(false));
        $this->getJson('/api/buy-requests')->assertForbidden();
        $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertForbidden();
        Sanctum::actingAs($this->seller());
        $owner->USR_STATUS = 'DEACTIVATED';
        $owner->save();
        $this->getJson('/api/buy-requests')->assertJsonCount(0, 'requests');
        $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertForbidden();
    }

    public function test_crop_catalog_requires_a_confirmed_canonical_name(): void
    {
        Sanctum::actingAs($this->user(true));
        $this->getJson('/api/buy-request-crops')->assertOk()->assertJsonFragment(['name' => 'Cabbage', 'aliases' => ['repolyo']]);
        foreach (['cabbge', 'Ineedcabbage', 'cabbage for my business'] as $crop) {
            $this->postJson('/api/buy-requests', ['crop' => $crop, 'quantity_kg' => 5, 'frequency' => 'weekly'])->assertUnprocessable();
        }
        $this->postJson('/api/buy-requests', ['crop' => 'Cabbage', 'quantity_kg' => 5, 'frequency' => 'weekly', 'note' => 'For my business'])->assertCreated()->assertJsonPath('request.crop', 'Cabbage');
    }

    public function test_sellers_receive_phone_and_only_explicit_precise_map_pins(): void
    {
        $owner = $this->user(true);
        $pin = $this->postRequest($owner, ['latitude' => 10.3178123, 'longitude' => 123.8742123]);
        $noPin = $this->postRequest($owner);
        $legacy = $this->postRequest($owner);
        BuyRequest::whereKey($legacy)->update(['BRQ_LATITUDE' => 10.32, 'BRQ_LONGITUDE' => 123.87, 'BRQ_HAS_PIN' => false]);
        Sanctum::actingAs($this->seller());
        $response = $this->getJson('/api/buy-requests')->assertOk()->assertJsonCount(3, 'requests');
        $rows = collect($response->json('requests'))->keyBy('id');
        $this->assertSame($owner->USR_MOBILE_NUMBER, $rows[$pin]['buyer']['phone']);
        $this->assertEqualsWithDelta(10.3178123, $rows[$pin]['location']['latitude'], 0.0000001);
        $this->assertEqualsWithDelta(123.8742123, $rows[$pin]['location']['longitude'], 0.0000001);
        $this->assertNull($rows[$noPin]['location']);
        $this->assertNull($rows[$legacy]['location']);
        $this->assertNull($rows[$legacy]['distance_km']);
    }

    public function test_validation_rejects_bad_quantity_and_partial_location(): void
    {
        Sanctum::actingAs($this->user(true));
        $this->postJson('/api/buy-requests', ['crop' => 'Pechay', 'quantity_kg' => -1, 'frequency' => 'daily'])->assertUnprocessable();
        $this->postJson('/api/buy-requests', ['crop' => 'Pechay', 'quantity_kg' => 1, 'frequency' => 'weekly', 'latitude' => 10])->assertUnprocessable();
        $this->assertSame(0, BuyRequest::count());
    }

    public function test_owner_can_edit_all_fields_before_responses_and_clear_pin(): void
    {
        Bus::fake();
        $owner = $this->user(true);
        $id = $this->postRequest($owner, ['latitude' => 10, 'longitude' => 123]);
        $created = BuyRequest::find($id)->BRQ_CREATED_AT;
        $this->patchJson('/api/buy-requests/'.$id, ['crop' => 'Tomato', 'quantity_kg' => 20.25, 'frequency' => 'one-time', 'note' => 'Changed', 'pickup_location' => 'Pusok', 'latitude' => null, 'longitude' => null, 'USR_ID' => 'WRONG1'])
            ->assertOk()->assertJsonPath('request.crop', 'Tomato')->assertJsonPath('request.quantity_kg', 20.25)->assertJsonPath('request.location', null);
        $row = BuyRequest::find($id);
        $this->assertNotNull($row->BRQ_UPDATED_AT);
        $this->assertEquals($created, $row->BRQ_CREATED_AT);
        $this->assertSame($owner->USR_ID, $row->USR_ID);
        $this->assertFalse((bool) $row->BRQ_HAS_PIN);
        Bus::assertNothingDispatched();
    }

    public function test_edit_is_owner_premium_only_and_validates_fields(): void
    {
        $this->withoutMiddleware(ThrottleRequests::class);
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        Sanctum::actingAs($this->user(true));
        $this->patchJson('/api/buy-requests/'.$id, ['quantity_kg' => 20])->assertForbidden();
        Sanctum::actingAs($owner);
        foreach ([['quantity_kg' => -1], ['quantity_kg' => 1.234], ['frequency' => 'daily'], ['crop' => 'random'], ['note' => str_repeat('x', 1001)], ['pickup_location' => str_repeat('x', 256)], ['latitude' => 10], ['longitude' => 181, 'latitude' => 10]] as $bad) {
            $this->patchJson('/api/buy-requests/'.$id, $bad)->assertUnprocessable();
        }
        $owner->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->subMinute()])->save();
        Sanctum::actingAs($owner->fresh());
        $this->patchJson('/api/buy-requests/'.$id, ['quantity_kg' => 20])->assertForbidden();
        $owner->forceFill(['USR_PREMIUM_EXPIRES_AT' => now()->addMonth()])->save();
        Sanctum::actingAs($owner->fresh());
        $this->deleteJson('/api/buy-requests/'.$id)->assertOk();
        $this->patchJson('/api/buy-requests/'.$id, ['quantity_kg' => 20])->assertNotFound();
    }

    public function test_response_locks_crop_but_other_edits_preserve_chat_and_queue_one_alert(): void
    {
        Bus::fake();
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        $seller = $this->seller();
        Sanctum::actingAs($seller);
        $thread = $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertCreated()->json('conversation.id');
        Sanctum::actingAs($owner);
        $this->patchJson('/api/buy-requests/'.$id, ['crop' => 'Tomato', 'quantity_kg' => 30])->assertUnprocessable()->assertJsonValidationErrors('crop');
        $this->assertEquals(15.5, BuyRequest::find($id)->BRQ_QUANTITY_KG);
        $this->patchJson('/api/buy-requests/'.$id, ['crop' => 'Pechay', 'quantity_kg' => 30, 'frequency' => 'one-time', 'pickup_location' => 'Pusok'])->assertOk()->assertJsonPath('request.response_count', 1);
        Bus::assertDispatched(SendBuyRequestUpdate::class, fn ($job) => $job->users === [$seller->USR_ID] && $job->requestId === $id && $job->queue === 'request-updates');
        Bus::assertDispatchedTimes(SendBuyRequestUpdate::class, 1);
        $this->getJson('/api/buy-requests/'.$id.'/conversations')->assertOk()->assertJsonPath('conversations.0.id', $thread);
        $this->postJson('/api/conversations/'.$thread.'/messages', ['content' => 'Updated details, same conversation'])->assertCreated();
    }

    public function test_unchanged_and_note_only_edits_do_not_notify(): void
    {
        Bus::fake();
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        $seller = $this->seller();
        Sanctum::actingAs($seller);
        $this->postJson('/api/buy-requests/'.$id.'/conversation')->assertCreated();
        Sanctum::actingAs($owner);
        $this->patchJson('/api/buy-requests/'.$id, ['quantity_kg' => 15.50, 'note' => 'Morning pickup preferred'])->assertOk()->assertJsonPath('request.updated_at', null);
        $this->patchJson('/api/buy-requests/'.$id, ['note' => 'New note'])->assertOk();
        $this->assertNotNull(BuyRequest::find($id)->BRQ_UPDATED_AT);
        Bus::assertNothingDispatched();
    }

    public function test_notification_retry_does_not_duplicate_inbox_rows(): void
    {
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        $seller = $this->seller();
        $sender = \Mockery::mock(EventPushSender::class);
        $sender->shouldReceive('configured')->twice()->andReturn(false);
        $job = new SendBuyRequestUpdate($id, [$seller->USR_ID], 'Quantity updated', (string) Str::uuid());
        $job->handle($sender);
        $job->handle($sender);
        $this->assertSame(1, UserNotification::where('USR_ID', $seller->USR_ID)->where('NOTIF_TYPE', 'BUY_REQUEST_UPDATED')->count());
    }

    public function test_push_retry_reuses_delivery_key_and_preserves_single_inbox_notice(): void
    {
        $owner = $this->user(true);
        $id = $this->postRequest($owner);
        $seller = $this->seller();
        config(['services.onesignal.app_id' => 'test-app', 'services.onesignal.rest_api_key' => 'test-key', 'services.onesignal.base_url' => 'https://push.test']);
        Http::fake(['*' => Http::sequence()->push([], 503)->push(['id' => 'accepted'], 200)]);
        $key = (string) Str::uuid();
        $job = new SendBuyRequestUpdate($id, [$seller->USR_ID], 'Quantity updated', $key);
        $sender = new EventPushSender;
        try {
            $job->handle($sender);
            $this->fail('An unaccepted push must be retried.');
        } catch (\RuntimeException $e) {
            $this->assertSame('Buy request update push was not accepted.', $e->getMessage());
        }
        $job->handle($sender);
        Http::assertSentCount(2);
        Http::assertSent(fn ($request) => $request['idempotency_key'] === $key && $request['include_aliases']['external_id'] === [$seller->USR_ID]);
        $this->assertSame(1, UserNotification::where('USR_ID', $seller->USR_ID)->where('NOTIF_TYPE', 'BUY_REQUEST_UPDATED')->count());
    }
}
