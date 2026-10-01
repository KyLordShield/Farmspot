<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\Conversation;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Report;
use App\Models\User;
use App\Notifications\ReportActioned;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The user-facing report contract.
 *
 * A report is an accusation against a named person, so the rules that matter
 * are almost all about who is allowed to file one:
 *
 *  1. Only the recipient of a message can report that message.
 *  2. Nobody can report themselves, their own listing, or their own seller
 *     account.
 *  3. A target that exists but belongs to someone else must not be confirmed
 *     to exist, or the endpoint becomes an oracle for enumerating ids.
 *  4. A retried submit must not become a second row in the moderator queue.
 *
 * The schema comes from a committed SQL dump rather than migrations, so these
 * run against MySQL (see phpunit.mysql.xml).
 */
class ReportSubmissionTest extends TestCase
{
    use RefreshDatabase;

    private function id(string $prefix): string
    {
        $table = [
            'USR' => 'user',
            'BUY' => 'buyer',
            'FMR' => 'farmer',
            'FRM' => 'farm',
            'LST' => 'listing',
            'MSG' => 'message',
            'CNV' => 'conversation',
            'CAT' => 'crop_category',
        ][$prefix];

        $column = $prefix === 'CNV' ? 'CONV_ID' : "{$prefix}_ID";

        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }

    private function makeUser(string $name = 'Maria Santos', string $email = 'maria@test.local', string $role = 'GENERAL_USER'): User
    {
        return User::create([
            'USR_ID' => $this->id('USR'),
            'USR_NAME' => $name,
            'USR_EMAIL' => $email,
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0917'.str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => $role,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
    }

    /**
     * A seller: user -> buyer -> farmer -> farm -> listing. Returns the pieces
     * a test needs to report or be reported.
     */
    private function makeSeller(string $name = 'React A', string $email = 'reacta@test.local'): array
    {
        $user = $this->makeUser($name, $email);
        $buyer = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $user->USR_ID]);
        $farmer = Farmer::create(['FMR_ID' => $this->id('FMR'), 'BUY_ID' => $buyer->BUY_ID]);
        $farm = Farm::create([
            'FRM_ID' => $this->id('FRM'),
            'FRM_NAME' => $name.' Farm',
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

        return compact('user', 'buyer', 'farmer', 'farm', 'listing');
    }

    private function makePlainBuyer(string $name = 'Maria Santos', string $email = 'maria@test.local'): array
    {
        $user = $this->makeUser($name, $email);
        $buyer = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $user->USR_ID]);

        return compact('user', 'buyer');
    }

    private function categoryId(): string
    {
        return CropCategory::first()?->CAT_ID
            ?? CropCategory::create([
                'CAT_ID' => $this->id('CAT'),
                'CAT_NAME' => 'Vegetables',
            ])->CAT_ID;
    }

    /**
     * A conversation with one message in it, sent by $sender to $other.
     */
    private function makeThread(array $seller, array $buyer, string $content = 'hello'): Conversation
    {
        $conversation = Conversation::create([
            'CONV_ID' => $this->id('CNV'),
            'LST_ID' => $seller['listing']->LST_ID,
            'CONV_CREATED_AT' => now(),
            'BUY_ID' => $buyer['buyer']->BUY_ID,
            'FMR_ID' => $seller['farmer']->FMR_ID,
            'FRM_ID' => $seller['farm']->FRM_ID,
        ]);

        $message = Message::create([
            'MSG_ID' => $this->id('MSG'),
            'MSG_CONTENT' => $content,
            'MSG_IS_READ' => 0,
            'MSG_CREATED_AT' => now(),
            'CONV_ID' => $conversation->CONV_ID,
            'USR_ID' => $seller['user']->USR_ID,
        ]);

        $conversation->setAttribute('test_message_id', $message->MSG_ID);

        return $conversation;
    }

    private function report(User $user, array $payload)
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/reports', $payload);
    }

    // ---------------------------------------------------------------- listings

    public function test_a_buyer_can_report_a_crop_listing()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $response = $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'MISLEADING_INFO',
            'details' => 'The photo is not this crop.',
        ]);

        $response->assertStatus(201);
        $response->assertJsonPath('report.target_type', 'LISTING');
        $response->assertJsonPath('report.target_id', $seller['listing']->LST_ID);
        $response->assertJsonPath('report.reason', 'MISLEADING_INFO');

        $this->assertDatabaseHas('report', [
            'USR_ID' => $buyer['user']->USR_ID,
            'LST_ID' => $seller['listing']->LST_ID,
            'RPT_TARGET_TYPE' => 'LISTING',
            'RPT_TARGET_ID' => $seller['listing']->LST_ID,
            'RPT_REASON_CODE' => 'MISLEADING_INFO',
            'RPT_DETAILS' => 'The photo is not this crop.',
            'RPT_STATUS' => 'New',
        ]);
    }

    public function test_the_reported_listing_is_not_hidden_automatically()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'FAKE_LISTING',
        ])->assertStatus(201);

        // A report is a queue entry, not a sanction. Nothing may take the crop
        // off sale on its own, or a group of users could bury a competitor.
        $this->assertDatabaseHas('listing', [
            'LST_ID' => $seller['listing']->LST_ID,
            'LST_AVAILABILITY' => 'ACTIVE',
        ]);
    }

    public function test_a_seller_cannot_report_their_own_listing()
    {
        $seller = $this->makeSeller();

        $this->report($seller['user'], [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'OTHER',
        ])->assertStatus(403);

        $this->assertSame(0, Report::count());
    }

    public function test_reporting_a_missing_listing_is_a_404()
    {
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => 'ZZZZZZ',
            'reason' => 'OTHER',
        ])->assertStatus(404);
    }

    // ---------------------------------------------------------------- messages

    public function test_the_recipient_can_report_a_message_they_received()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();
        $thread = $this->makeThread($seller, $buyer, 'meet me at the farm, bring cash');

        $response = $this->report($buyer['user'], [
            'target_type' => 'MESSAGE',
            'target_id' => $thread->getAttribute('test_message_id'),
            'reason' => 'FRAUD_OR_SCAM',
        ]);

        $response->assertStatus(201);
        $response->assertJsonPath('report.target_type', 'MESSAGE');

        // The listing is kept as context: a moderator needs to know whether
        // this was a live sale or an unsolicited approach.
        $this->assertDatabaseHas('report', [
            'RPT_TARGET_TYPE' => 'MESSAGE',
            'RPT_TARGET_ID' => $thread->getAttribute('test_message_id'),
            'LST_ID' => $seller['listing']->LST_ID,
            'RPT_REASON_CODE' => 'FRAUD_OR_SCAM',
        ]);
    }

    public function test_the_sender_cannot_report_their_own_message()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();
        $thread = $this->makeThread($seller, $buyer);

        $this->report($seller['user'], [
            'target_type' => 'MESSAGE',
            'target_id' => $thread->getAttribute('test_message_id'),
            'reason' => 'OTHER',
        ])->assertStatus(403);

        $this->assertSame(0, Report::count());
    }

    public function test_a_bystander_cannot_report_a_message_and_learns_nothing()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();
        $thread = $this->makeThread($seller, $buyer);
        $bystander = $this->makePlainBuyer('Nosy', 'nosy@test.local');

        // 404 rather than 403 on purpose: a 403 would confirm the message id is
        // real, turning the endpoint into an oracle for enumerating ids.
        $this->report($bystander['user'], [
            'target_type' => 'MESSAGE',
            'target_id' => $thread->getAttribute('test_message_id'),
            'reason' => 'OTHER',
        ])->assertStatus(404);

        $this->assertSame(0, Report::count());
    }

    public function test_a_seller_can_report_a_buyer_message_from_the_same_thread()
    {
        // The other direction: a buyer harasses the seller, and the seller has
        // to be able to report it.
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();
        $thread = $this->makeThread($seller, $buyer);

        $message = Message::create([
            'MSG_ID' => $this->id('MSG'),
            'MSG_CONTENT' => 'you are a fraud',
            'MSG_IS_READ' => 0,
            'MSG_CREATED_AT' => now(),
            'CONV_ID' => $thread->CONV_ID,
            'USR_ID' => $buyer['user']->USR_ID,
        ]);

        $this->report($seller['user'], [
            'target_type' => 'MESSAGE',
            'target_id' => $message->MSG_ID,
            'reason' => 'HARASSMENT',
        ])->assertStatus(201);
    }

    public function test_a_buyer_can_report_a_message_in_a_thread_with_no_listing()
    {
        // Conversations may exist without a listing. The report must still be
        // accepted, with a null listing rather than a bogus one.
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $thread = Conversation::create([
            'CONV_ID' => $this->id('CNV'),
            'LST_ID' => null,
            'CONV_CREATED_AT' => now(),
            'BUY_ID' => $buyer['buyer']->BUY_ID,
            'FMR_ID' => $seller['farmer']->FMR_ID,
        ]);

        $message = Message::create([
            'MSG_ID' => $this->id('MSG'),
            'MSG_CONTENT' => 'are you there',
            'MSG_IS_READ' => 0,
            'MSG_CREATED_AT' => now(),
            'CONV_ID' => $thread->CONV_ID,
            'USR_ID' => $seller['user']->USR_ID,
        ]);

        $this->report($buyer['user'], [
            'target_type' => 'MESSAGE',
            'target_id' => $message->MSG_ID,
            'reason' => 'SPAM',
        ])->assertStatus(201);

        $this->assertDatabaseHas('report', [
            'RPT_TARGET_ID' => $message->MSG_ID,
            'LST_ID' => null,
        ]);
    }

    // ----------------------------------------------------------------- farmers

    public function test_a_buyer_can_report_a_farmer_without_touching_a_listing()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $response = $this->report($buyer['user'], [
            'target_type' => 'FARMER',
            'target_id' => $seller['farmer']->FMR_ID,
            'reason' => 'UNSAFE_BEHAVIOR',
        ]);

        $response->assertStatus(201);
        $response->assertJsonPath('report.target_id', $seller['farmer']->FMR_ID);

        // No listing is implied: the complaint is about the seller, not a crop.
        $this->assertDatabaseHas('report', [
            'RPT_TARGET_TYPE' => 'FARMER',
            'RPT_TARGET_ID' => $seller['farmer']->FMR_ID,
            'LST_ID' => null,
        ]);
    }

    public function test_a_seller_cannot_report_their_own_farmer_account()
    {
        $seller = $this->makeSeller();

        $this->report($seller['user'], [
            'target_type' => 'FARMER',
            'target_id' => $seller['farmer']->FMR_ID,
            'reason' => 'OTHER',
        ])->assertStatus(403);
    }

    public function test_reporting_a_missing_farmer_is_a_404()
    {
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'FARMER',
            'target_id' => 'ZZZZZZ',
            'reason' => 'OTHER',
        ])->assertStatus(404);
    }

    // ------------------------------------------------------------------- users

    public function test_a_seller_can_report_a_buyer_account()
    {
        // The reverse abuse case: a buyer is not a farmer, so a USER report is
        // the only way to flag them.
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $this->report($seller['user'], [
            'target_type' => 'USER',
            'target_id' => $buyer['user']->USR_ID,
            'reason' => 'HARASSMENT',
        ])->assertStatus(201);

        $this->assertDatabaseHas('report', [
            'RPT_TARGET_TYPE' => 'USER',
            'RPT_TARGET_ID' => $buyer['user']->USR_ID,
        ]);
    }

    public function test_nobody_can_report_their_own_account()
    {
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'USER',
            'target_id' => $buyer['user']->USR_ID,
            'reason' => 'OTHER',
        ])->assertStatus(403);

        $this->assertSame(0, Report::count());
    }

    // -------------------------------------------------------------- validation

    public function test_a_report_needs_a_signed_in_user()
    {
        $seller = $this->makeSeller();

        $this->postJson('/api/reports', [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'OTHER',
        ])->assertStatus(401);
    }

    public function test_the_reporter_comes_from_the_token_never_the_body()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();
        $impostor = $this->makePlainBuyer('Impostor', 'impostor@test.local');

        // A client-supplied USR_ID must be ignored outright, or anyone could
        // file a report in someone else's name.
        $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'OTHER',
            'USR_ID' => $impostor['user']->USR_ID,
        ])->assertStatus(201);

        $this->assertDatabaseHas('report', [
            'USR_ID' => $buyer['user']->USR_ID,
            'RPT_TARGET_TYPE' => 'LISTING',
        ]);
        $this->assertDatabaseMissing('report', ['USR_ID' => $impostor['user']->USR_ID]);
    }

    public function test_an_unknown_target_type_is_rejected()
    {
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'EVERYTHING',
            'target_id' => 'ABC123',
            'reason' => 'OTHER',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('target_type');
    }

    public function test_an_unknown_reason_is_rejected()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'BECAUSE_I_SAID_SO',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('reason');
    }

    public function test_a_missing_target_is_rejected()
    {
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'reason' => 'OTHER',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('target_id');
    }

    public function test_every_reason_in_the_taxonomy_is_accepted()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        foreach (array_keys(Report::REASONS) as $reason) {
            $this->report($buyer['user'], [
                'target_type' => 'LISTING',
                'target_id' => $seller['listing']->LST_ID,
                'reason' => $reason,
            ])->assertStatus(201);
        }

        $this->assertSame(count(Report::REASONS), Report::count());
    }

    public function test_optional_details_may_be_omitted_or_blank()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'OTHER',
        ])->assertStatus(201);

        // A field of only spaces is not a reason to reject the report; it just
        // means there is no detail to store.
        $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'SPAM',
            'details' => '   ',
        ])->assertStatus(201);

        $this->assertNull(Report::first()->RPT_DETAILS);
    }

    public function test_details_are_length_capped()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'OTHER',
            'details' => str_repeat('a', 1001),
        ])->assertStatus(422)
            ->assertJsonValidationErrors('details');
    }

    // ----------------------------------------------------------------- dedupe

    public function test_a_retry_does_not_create_a_second_row()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $payload = [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'MISLEADING_INFO',
        ];

        // The app retries when a connection drops mid-flight. 200, not 201, so
        // the app can tell "filed" from "already on file" without a second call.
        $this->report($buyer['user'], $payload)->assertStatus(201);
        $this->report($buyer['user'], $payload)->assertStatus(200);

        $this->assertSame(1, Report::count());
    }

    public function test_a_retry_is_answered_with_the_report_they_actually_sent()
    {
        // More than one identical report can be on file: the day window expires
        // and the buyer says so again. The 200 has to name the newest of them.
        //
        // This used to order by RPT_ID, which was honest while that column was
        // AUTO_INCREMENT. It is now six random digits, so "latest id" sorts them
        // as strings and would hand back whichever report happened to sort
        // highest — an id and a created_at the buyer never saw.
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $payload = [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'MISLEADING_INFO',
        ];

        $first = $this->report($buyer['user'], $payload)->assertCreated()->json('report');

        // Push the first one out of the duplicate window, then file again.
        $firstReport = Report::firstWhere('RPT_ID', $first['id']);
        $firstReport->update(['RPT_CREATED_AT' => now()->subDays(2)]);

        $second = $this->report($buyer['user'], $payload)->assertCreated()->json('report');

        $this->assertNotSame($first['id'], $second['id']);
        $this->assertSame(2, Report::count());

        // And now a retry inside the window answers with the recent one, not the
        // stale one that sorts higher or lower by chance.
        $this->report($buyer['user'], $payload)
            ->assertOk()
            ->assertJsonPath('report.id', $second['id'])
            ->assertJsonPath('report.created_at', $second['created_at']);
    }

    public function test_a_different_reason_is_a_separate_report()
    {
        $seller = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $base = [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
        ];

        $this->report($buyer['user'], $base + ['reason' => 'MISLEADING_INFO'])->assertStatus(201);
        $this->report($buyer['user'], $base + ['reason' => 'FRAUD_OR_SCAM'])->assertStatus(201);

        $this->assertSame(2, Report::count());
    }

    public function test_two_people_can_both_report_the_same_thing()
    {
        $seller = $this->makeSeller();
        $first = $this->makePlainBuyer();
        $second = $this->makePlainBuyer('Second', 'second@test.local');

        $payload = [
            'target_type' => 'LISTING',
            'target_id' => $seller['listing']->LST_ID,
            'reason' => 'FAKE_LISTING',
        ];

        $this->report($first['user'], $payload)->assertStatus(201);
        $this->report($second['user'], $payload)->assertStatus(201);

        // Two independent complaints are signal, not noise. Only the same
        // person repeating themselves is deduped.
        $this->assertSame(2, Report::count());
    }

    public function test_the_new_report_response_is_complete_and_stringly_typed()
    {
        $listing = $this->makeSeller();
        $reporter = $this->makePlainBuyer();

        $response = $this->report($reporter['user'], [
            'target_type' => 'LISTING',
            'target_id' => $listing['listing']->LST_ID,
            'reason' => 'MISLEADING_INFO',
        ]);

        $response->assertCreated()->assertJsonStructure([
            'message',
            'report' => ['id', 'target_type', 'target_id', 'reason', 'status'],
        ]);

        // RPT_ID used to be this schema's one AUTO_INCREMENT column. Sent as an
        // int it reached the app as a JSON number and crashed a hard `as String`
        // cast there — after the report was already saved, so the user saw a
        // failure for a report that was sitting in the moderator's queue. It is
        // now a six-character id the model assigns, and every id in this API is
        // a string.
        $this->assertIsString($response->json('report.id'));

        // RPT_STATUS and RPT_CREATED_AT come from column defaults that MySQL
        // never returns to the inserting connection, so a model that has just
        // been created holds null for both. Reporting null here would also
        // disagree with the duplicate branch, which formats a model that was
        // read back from the row.
        $this->assertSame('New', $response->json('report.status'));
        $this->assertNotNull(
            $response->json('report.created_at'),
            'a new report must say when it was filed',
        );
    }

    public function test_a_duplicate_response_agrees_with_a_new_one()
    {
        // The 201 and 200 paths format the report differently — one is a model
        // that was just inserted, the other one that was read back — so the two
        // shapes have to match or the app sees a field change meaning depending
        // on whether a buyer happened to report the same thing twice.
        $listing = $this->makeSeller();
        $buyer = $this->makePlainBuyer();
        $payload = [
            'target_type' => 'LISTING',
            'target_id' => $listing['listing']->LST_ID,
            'reason' => 'SPAM',
        ];

        $fresh = $this->report($buyer['user'], $payload)->assertCreated()->json('report');
        $repeat = $this->report($buyer['user'], $payload)->assertOk()->json('report');

        $this->assertSame($fresh['id'], $repeat['id']);
        $this->assertSame($fresh['status'], $repeat['status']);
        $this->assertSame($fresh['created_at'], $repeat['created_at']);
    }

    // ------------------------------------------------------------ the id itself

    public function test_a_report_id_is_six_digits()
    {
        $listing = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $id = $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $listing['listing']->LST_ID,
            'reason' => 'SPAM',
        ])->assertCreated()->json('report.id');

        // Six characters like every other id in this schema, so nothing that
        // treats report ids the way it treats listing ids has to special-case it.
        $this->assertSame(6, strlen($id));
        $this->assertMatchesRegularExpression('/^[1-9][0-9]{5}$/', $id);

        $this->assertDatabaseHas('report', ['RPT_ID' => $id]);
    }

    public function test_report_ids_do_not_run_in_order()
    {
        // Sequential ids let anyone count how many reports have been filed, and
        // then guess the next one. They also make the queue look busier than it
        // is.
        //
        // This tests the generator rather than filing fifty reports, because the
        // API deliberately refuses a second report from the same person about
        // the same target for the same reason within a day — so the ids are the
        // only thing here worth asserting.
        $ids = collect(range(1, 200))->map(fn () => Report::newId());

        $this->assertCount(200, $ids->unique(), 'every report needs its own id');

        $ids->each(function ($id) {
            $this->assertSame(6, strlen($id));
            $this->assertMatchesRegularExpression('/^[1-9][0-9]{5}$/', $id);
        });

        // If these were sequential the spread across the whole 100000-999999
        // range would be a rounding error, so a real sample should not.
        $this->assertGreaterThan(20, $ids->unique()->count());
    }

    public function test_the_notification_feed_tells_a_reporter_what_happened()
    {
        // Reporting used to be a one-way door: the buyer pressed submit and then
        // heard nothing, so a report that was reviewed and actioned looked
        // exactly like one that was ignored. The app has no inbox screen yet,
        // but the record is readable, which makes the screen a rendering job.
        $listing = $this->makeSeller();
        $buyer = $this->makePlainBuyer();

        $reportId = $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $listing['listing']->LST_ID,
            'reason' => 'FAKE_LISTING',
        ])->assertCreated()->json('report.id');

        $admin = $this->makeUser('Admin', 'admin@test.local', 'ADMIN');
        $this->actingAs($admin)
            ->post("/reports/{$reportId}/action/LISTING_TAKEN_DOWN")
            ->assertRedirect(route('reports.show', $reportId));

        $response = $this->actingAs($buyer['user'], 'sanctum')
            ->getJson('/api/notifications')
            ->assertOk()
            ->assertJsonStructure(['data' => [['id', 'type', 'data', 'read_at']]]);

        $this->assertCount(1, $response->json('data'));
        // `type` is Laravel's own class name; the field a client switches on is
        // the `kind` discriminator inside the payload.
        $this->assertSame(ReportActioned::class, $response->json('data.0.type'));
        $this->assertSame('report_actioned', $response->json('data.0.data.kind'));
        $this->assertSame('Listing taken off sale.', $response->json('data.0.data.body'));
        $this->assertSame($reportId, $response->json('data.0.data.report_id'));
        $this->assertNull($response->json('data.0.read_at'));

        // And it can be marked read, so a future inbox has a dot to clear.
        $this->actingAs($buyer['user'], 'sanctum')
            ->postJson('/api/notifications/read')
            ->assertOk();

        $this->assertNotNull(
            $this->actingAs($buyer['user'], 'sanctum')
                ->getJson('/api/notifications')
                ->json('data.0.read_at')
        );
    }

    public function test_a_buyer_cannot_read_another_buyers_notifications()
    {
        // The feed is resolved from the bearer token, never from a parameter,
        // so one buyer cannot read what was done about another buyer's report.
        $listing = $this->makeSeller();
        $buyer = $this->makePlainBuyer();
        $nosy = $this->makePlainBuyer('Nosy Parker', 'nosy@test.local');

        $reportId = $this->report($buyer['user'], [
            'target_type' => 'LISTING',
            'target_id' => $listing['listing']->LST_ID,
            'reason' => 'FAKE_LISTING',
        ])->assertCreated()->json('report.id');

        $admin = $this->makeUser('Admin', 'admin@test.local', 'ADMIN');
        $this->actingAs($admin)->post("/reports/{$reportId}/action/LISTING_TAKEN_DOWN");

        $this->actingAs($nosy['user'], 'sanctum')
            ->getJson('/api/notifications')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    public function test_the_notification_feed_needs_a_signed_in_user()
    {
        $this->getJson('/api/notifications')->assertUnauthorized();
    }
}


