<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\Conversation;
use App\Models\CropCategory;
use App\Models\Farmer;
use App\Models\Farm;
use App\Models\Listing;
use App\Models\Message;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * The in-app buyer <-> seller messaging contract.
 *
 * The schema for this project comes from a committed SQL dump rather than from
 * migrations, so these run against MySQL (see phpunit.mysql.xml). Two rules are
 * worth more than the rest of this file combined:
 *
 *  1. Only a participant may read or post to a thread. Everything else is 403.
 *  2. A listing is the thread key. Asking twice returns the same conversation.
 */
class ConversationMessagingTest extends TestCase
{
    use RefreshDatabase;

    private User $sellerUser;

    private User $buyerUser;

    private Listing $listing;

    /** The seller: a user who has a buyer row, a farmer row and a farm. */
    private function makeSeller(string $name = 'React A', string $email = 'reacta@test.local'): array
    {
        $user = $this->makeUser($name, $email);
        $buyer = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $user->USR_ID]);
        $farmer = Farmer::create(['FMR_ID' => $this->id('FMR'), 'BUY_ID' => $buyer->BUY_ID]);
        $farm = Farm::create([
            'FRM_ID' => $this->id('FRM'),
            'FRM_NAME' => $name . ' Farm',
            'FRM_BARANGAY' => 'Sudlon II',
            'FRM_LATITUDE' => 10.30,
            'FRM_LONGITUDE' => 123.89,
            'FRM_CREATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
        ]);
        $listing = Listing::create([
            'LST_ID' => $this->id('LST'),
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
            'FRM_ID' => $farm->FRM_ID,
            'CAT_ID' => $this->categoryId(),
            'LST_CROP_ICON' => 'Carrot',
        ]);

        return [$user, $listing, $buyer, $farmer, $farm];
    }

    private function makeUser(string $name, string $email): User
    {
        return User::create([
            'USR_ID' => $this->id('USR'),
            'USR_NAME' => $name,
            'USR_EMAIL' => $email,
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0917' . str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
    }

    private function id(string $prefix): string
    {
        $table = [
            'USR' => 'user',
            'BUY' => 'buyer',
            'FMR' => 'farmer',
            'FRM' => 'farm',
            'LST' => 'listing',
            'CAT' => 'crop_category',
        ][$prefix];

        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where("{$prefix}_ID", $id)->exists());

        return $id;
    }

    private function categoryId(): string
    {
        return CropCategory::first()?->CAT_ID
            ?? CropCategory::create([
                'CAT_ID' => $this->id('CAT'),
                'CAT_NAME' => 'Vegetables',
            ])->CAT_ID;
    }

    private function makePlainBuyer(string $name = 'Maria Santos', string $email = 'maria@test.local'): array
    {
        $user = $this->makeUser($name, $email);
        $buyer = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $user->USR_ID]);

        return [$user, $buyer];
    }

    private function startThread(User $user, Listing $listing): Conversation
    {
        $response = $this->actingAs($user, 'sanctum')
            ->postJson('/api/conversations', ['LST_ID' => $listing->LST_ID]);

        $response->assertSuccessful();

        return Conversation::find($response->json('conversation.id'));
    }

    private function postMessage(User $user, string $conversationId, string $content): TestResponse
    {
        return $this->actingAs($user, 'sanctum')
            ->postJson("/api/conversations/{$conversationId}/messages", ['content' => $content]);
    }

    public function test_starting_a_thread_is_idempotent_per_listing_and_buyer()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();

        $first = $this->actingAs($buyerUser, 'sanctum')
            ->postJson('/api/conversations', ['LST_ID' => $listing->LST_ID]);
        $first->assertStatus(201);
        $first->assertJsonPath('conversation.listing_id', $listing->LST_ID);
        $first->assertJsonPath('conversation.other_party.name', 'React A');

        $second = $this->actingAs($buyerUser, 'sanctum')
            ->postJson('/api/conversations', ['LST_ID' => $listing->LST_ID]);
        $second->assertSuccessful();

        $this->assertSame(
            $first->json('conversation.id'),
            $second->json('conversation.id'),
            'a second tap must land in the same thread, not a duplicate'
        );
        $this->assertSame(1, Conversation::count());
    }

    public function test_a_buyer_who_never_activated_selling_can_still_start_a_thread()
    {
        [, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();

        $response = $this->actingAs($buyerUser, 'sanctum')
            ->postJson('/api/conversations', ['LST_ID' => $listing->LST_ID]);

        $response->assertStatus(201);
        $this->assertNotNull(
            $response->json('conversation.buyer_id'),
            'a buyer row is created lazily so the foreign key can be filled'
        );
        $this->assertSame(
            1,
            Buyer::where('USR_ID', $buyerUser->USR_ID)->count(),
            'exactly one buyer row, reused rather than duplicated'
        );
    }

    public function test_a_seller_cannot_message_their_own_listing()
    {
        [$sellerUser, $listing] = $this->makeSeller();

        $this->actingAs($sellerUser, 'sanctum')
            ->postJson('/api/conversations', ['LST_ID' => $listing->LST_ID])
            ->assertStatus(422);

        $this->assertSame(0, Conversation::count());
    }

    public function test_an_unknown_listing_is_a_404()
    {
        [$buyerUser] = $this->makePlainBuyer();

        $this->actingAs($buyerUser, 'sanctum')
            ->postJson('/api/conversations', ['LST_ID' => 'NOPE00'])
            ->assertStatus(404);
    }

    public function test_the_inbox_shows_each_thread_once_with_the_callers_role()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $buyerInbox = $this->actingAs($buyerUser, 'sanctum')->getJson('/api/conversations');
        $buyerInbox->assertOk();
        $buyerInbox->assertJsonCount(1, 'conversations');
        $buyerInbox->assertJsonPath('conversations.0.id', $thread->CONV_ID);
        $buyerInbox->assertJsonPath('conversations.0.my_role', 'BUYER');

        $sellerInbox = $this->actingAs($sellerUser, 'sanctum')->getJson('/api/conversations');
        $sellerInbox->assertOk();
        $sellerInbox->assertJsonCount(1, 'conversations');
        $sellerInbox->assertJsonPath('conversations.0.id', $thread->CONV_ID);
        $sellerInbox->assertJsonPath('conversations.0.my_role', 'SELLER');
        $sellerInbox->assertJsonPath('conversations.0.other_party.name', 'Maria Santos');
    }

    public function test_an_account_with_no_buyer_or_farmer_row_sees_an_empty_inbox()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $this->startThread($buyerUser, $listing);

        // A third party with no buyer/farmer row must see nothing at all.
        $stranger = $this->makeUser('Nosy Neighbour', 'nosy@test.local');

        $this->actingAs($stranger, 'sanctum')
            ->getJson('/api/conversations')
            ->assertOk()
            ->assertExactJson(['conversations' => []]);
    }

    public function test_both_sides_can_post_and_each_message_is_flagged_for_its_reader()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, 'Is the carrot available?')
            ->assertStatus(201)
            ->assertJsonPath('message.is_mine', true)
            ->assertJsonPath('message.content', 'Is the carrot available?');

        $sellerView = $this->actingAs($sellerUser, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages");
        $sellerView->assertOk();
        $sellerView->assertJsonPath('messages.0.is_mine', false,
            'the same row must read as "not mine" for the other participant');

        $this->postMessage($sellerUser, $thread->CONV_ID, 'Yes, plenty!')->assertStatus(201);
    }

    public function test_a_sent_message_starts_unread_so_the_recipients_badge_lights_up()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, 'Still there?')->assertStatus(201);

        $this->actingAs($sellerUser, 'sanctum')
            ->getJson('/api/conversations')
            ->assertJsonPath('conversations.0.unread_count', 1);

        $this->assertSame(
            0,
            (int) Message::where('CONV_ID', $thread->CONV_ID)->value('MSG_IS_READ'),
            'a message must not be born read, or the recipient never sees a badge'
        );
    }

    public function test_opening_a_thread_marks_the_other_sides_messages_read()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);
        $this->postMessage($buyerUser, $thread->CONV_ID, 'Still there?')->assertStatus(201);

        $this->actingAs($sellerUser, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages")
            ->assertOk();

        $this->actingAs($sellerUser, 'sanctum')
            ->getJson('/api/conversations')
            ->assertJsonPath('conversations.0.unread_count', 0);

        $this->assertSame(
            1,
            (int) Message::where('CONV_ID', $thread->CONV_ID)->value('MSG_IS_READ')
        );
    }

    public function test_the_sender_never_counts_their_own_messages_as_unread()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, 'mine')->assertStatus(201);

        $this->actingAs($buyerUser, 'sanctum')
            ->getJson('/api/conversations')
            ->assertJsonPath('conversations.0.unread_count', 0);
    }

    public function test_polling_returns_only_what_is_newer_than_the_cursor()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, 'first')->assertStatus(201);
        $all = $this->actingAs($buyerUser, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages");
        $all->assertJsonCount(1, 'messages');
        $cursor = $all->json('messages.0.id');

        // Nothing new yet: an incremental read must be empty, not the whole thread.
        $this->actingAs($buyerUser, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages?after={$cursor}")
            ->assertOk()
            ->assertJsonCount(0, 'messages');

        $this->postMessage($sellerUser, $thread->CONV_ID, 'second')->assertStatus(201);

        $incremental = $this->actingAs($buyerUser, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages?after={$cursor}");
        $incremental->assertOk();
        $this->assertCount(1, $incremental->json('messages'));
        $this->assertSame('second', $incremental->json('messages.0.content'));
        $this->assertTrue($incremental->json('messages.0.is_mine') === false);
    }

    public function test_messages_sharing_a_timestamp_are_still_delivered()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        // Same second, which is all a `datetime` column can express. The ids are
        // random, so the second message deliberately sorts *before* the first
        // alphabetically: ordering by (time, id) would swallow it forever. Only a
        // monotonic cursor gets this right.
        $sameSecond = now();
        foreach (['ZZZZ01', 'AAAA01'] as $content) {
            Message::create([
                'MSG_ID' => $content,
                'CONV_ID' => $thread->CONV_ID,
                'USR_ID' => $buyerUser->USR_ID,
                'MSG_CONTENT' => $content,
                'MSG_IS_READ' => 1,
                'MSG_CREATED_AT' => $sameSecond,
            ]);
        }

        $response = $this->actingAs($sellerUser, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages?after=ZZZZ01");

        $response->assertOk();
        $this->assertCount(
            1,
            $response->json('messages'),
            'the later-inserted message must survive a same-second cursor'
        );
        $this->assertSame('AAAA01', $response->json('messages.0.id'));
    }

    public function test_the_full_thread_is_returned_in_insertion_order()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, 'one')->assertStatus(201);
        $this->postMessage($sellerUser, $thread->CONV_ID, 'two')->assertStatus(201);
        $this->postMessage($buyerUser, $thread->CONV_ID, 'three')->assertStatus(201);

        $response = $this->actingAs($buyerUser, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages");

        $response->assertOk();
        $this->assertSame(
            ['one', 'two', 'three'],
            array_column($response->json('messages'), 'content'),
            'history must read oldest first even when ids sort the other way'
        );
    }

    public function test_a_cursor_from_another_thread_is_ignored_rather_than_trusting_it()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);
        $this->postMessage($buyerUser, $thread->CONV_ID, 'mine')->assertStatus(201);

        // A message that exists, but in a different thread entirely.
        $otherThread = $this->startThread(
            $this->makePlainBuyer('Another Buyer', 'other@test.local')[0],
            $listing
        );
        $foreign = Message::create([
            'MSG_ID' => 'OTHER1',
            'CONV_ID' => $otherThread->CONV_ID,
            'USR_ID' => $sellerUser->USR_ID,
            'MSG_CONTENT' => 'unrelated',
            'MSG_IS_READ' => 1,
            'MSG_CREATED_AT' => now()->addDay(),
        ]);

        $response = $this->actingAs($sellerUser, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages?after={$foreign->MSG_ID}");

        $response->assertOk();
        $this->assertCount(
            1,
            $response->json('messages'),
            'a cursor from another thread is treated as unknown, falling back to full history'
        );
    }

    public function test_a_stranger_cannot_read_or_post_to_a_thread()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);
        [$stranger] = $this->makePlainBuyer('Nosy Neighbour', 'nosy@test.local');

        $this->actingAs($stranger, 'sanctum')
            ->getJson("/api/conversations/{$thread->CONV_ID}/messages")
            ->assertStatus(403);

        $this->postMessage($stranger, $thread->CONV_ID, 'let me in')->assertStatus(403);

        $this->assertSame(0, Message::count(), 'a rejected post must not be stored');
    }

    public function test_a_missing_thread_is_a_404_rather_than_a_403()
    {
        [$buyerUser] = $this->makePlainBuyer();

        $this->actingAs($buyerUser, 'sanctum')
            ->getJson('/api/conversations/NOPE00/messages')
            ->assertStatus(404);
    }

    public function test_an_empty_or_whitespace_message_is_rejected()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, '   ')->assertStatus(422);
        $this->postMessage($buyerUser, $thread->CONV_ID, '')->assertStatus(422);

        $this->assertSame(0, Message::count());
    }

    public function test_a_message_longer_than_the_limit_is_rejected()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, str_repeat('a', 1001))->assertStatus(422);
        $this->postMessage($buyerUser, $thread->CONV_ID, str_repeat('a', 1000))->assertStatus(201);
    }

    public function test_the_inbox_preview_is_updated_by_the_latest_message()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, 'first')->assertStatus(201);
        $this->postMessage($sellerUser, $thread->CONV_ID, 'the latest')->assertStatus(201);

        $this->actingAs($buyerUser, 'sanctum')
            ->getJson('/api/conversations')
            ->assertJsonPath('conversations.0.last_message', 'the latest');
    }

    public function test_a_long_message_preview_is_truncated_to_the_column_width()
    {
        [$sellerUser, $listing] = $this->makeSeller();
        [$buyerUser] = $this->makePlainBuyer();
        $thread = $this->startThread($buyerUser, $listing);

        $this->postMessage($buyerUser, $thread->CONV_ID, str_repeat('b', 900))->assertStatus(201);

        $preview = $this->actingAs($buyerUser, 'sanctum')
            ->getJson('/api/conversations')
            ->json('conversations.0.last_message');

        $this->assertSame(500, mb_strlen($preview));
    }

    public function test_conversation_and_message_routes_require_authentication()
    {
        $this->postJson('/api/conversations', ['LST_ID' => 'LST0001'])->assertUnauthorized();
        $this->getJson('/api/conversations')->assertUnauthorized();
        $this->getJson('/api/conversations/CNV0001/messages')->assertUnauthorized();
        $this->postJson('/api/conversations/CNV0001/messages', ['content' => 'hi'])
            ->assertUnauthorized();
    }
}
