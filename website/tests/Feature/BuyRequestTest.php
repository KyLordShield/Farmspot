<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\BuyRequest;
use App\Models\Conversation;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
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
}
