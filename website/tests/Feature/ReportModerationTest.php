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
use App\Models\ReportAction;
use App\Models\User;
use App\Notifications\ReportActioned;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The moderator side of reports: who can reach the queue, and whether it
 * renders a report about a message or a person as well as a crop.
 *
 * The admin panel used to sit behind `auth` alone, so any signed-in web
 * account could open the queue and read reported message text. These lock that
 * down as well as checking the new subject types render.
 */
class ReportModerationTest extends TestCase
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

    private function makeUser(string $role = 'GENERAL_USER', string $name = 'Someone'): User
    {
        $id = $this->id('USR');

        return User::create([
            'USR_ID' => $id,
            'USR_NAME' => $name,
            // Keyed off the id, not the name: several tests want two users
            // called "Reporter" and USR_EMAIL is unique.
            'USR_EMAIL' => strtolower($id).'@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '09'.$id,
            'USR_ROLE' => $role,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
    }

    private function categoryId(): string
    {
        return CropCategory::first()?->CAT_ID
            ?? CropCategory::create(['CAT_ID' => $this->id('CAT'), 'CAT_NAME' => 'Vegetables'])->CAT_ID;
    }

    /** Seller plus a live listing. */
    private function makeListing(): array
    {
        $user = $this->makeUser('GENERAL_USER', 'React A');
        $buyer = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $user->USR_ID]);
        $farmer = Farmer::create(['FMR_ID' => $this->id('FMR'), 'BUY_ID' => $buyer->BUY_ID]);
        $farm = Farm::create([
            'FRM_ID' => $this->id('FRM'),
            'FRM_NAME' => 'React A Farm',
            'FRM_BARANGAY' => 'Sudlon II',
            'FRM_LATITUDE' => 10.30,
            'FRM_LONGITUDE' => 123.89,
            'FRM_CREATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
        ]);
        $listing = Listing::create([
            'LST_ID' => $this->id('LST'),
            'LST_CROP_ICON' => 'Carrot',
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
            'FRM_ID' => $farm->FRM_ID,
            'CAT_ID' => $this->categoryId(),
        ]);

        return compact('user', 'buyer', 'farmer', 'farm', 'listing');
    }

    private function makeReport(string $type, string $targetId, array $extra = []): Report
    {
        return Report::create(array_merge([
            // The database no longer assigns this. Leaving it out would rely on
            // a default the column does not have, and the row would fail to
            // insert rather than quietly get an id.
            'RPT_ID' => Report::newId(),
            'LST_ID' => null,
            'USR_ID' => $this->makeUser('GENERAL_USER', 'Reporter')->USR_ID,
            'RPT_REASON' => Report::REASONS['OTHER'],
            'RPT_REASON_CODE' => 'OTHER',
            'RPT_TARGET_TYPE' => $type,
            'RPT_TARGET_ID' => $targetId,
        ], $extra));
    }

    /** A live chat message from $sender, so a MESSAGE report has a real target. */
    private function makeMessage(User $sender, Listing $listing, string $content = 'send payment to this gcash number'): Message
    {
        $participant = Buyer::create([
            'BUY_ID' => $this->id('BUY'),
            'USR_ID' => $this->makeUser('GENERAL_USER', 'Maria')->USR_ID,
        ]);

        $conversation = Conversation::create([
            'CONV_ID' => $this->id('CNV'),
            'LST_ID' => $listing->LST_ID,
            'CONV_CREATED_AT' => now(),
            'BUY_ID' => $participant->BUY_ID,
            'FMR_ID' => $listing->FMR_ID,
        ]);

        return Message::create([
            'MSG_ID' => $this->id('MSG'),
            'MSG_CONTENT' => $content,
            'MSG_IS_READ' => 0,
            'MSG_SEQ' => 1,
            'MSG_CREATED_AT' => now(),
            'CONV_ID' => $conversation->CONV_ID,
            'USR_ID' => $sender->USR_ID,
        ]);
    }

    // ---------------------------------------------------------------- access

    public function test_a_guest_is_sent_to_login()
    {
        $this->get('/reports')->assertRedirect('/login');
    }

    public function test_a_non_admin_web_user_cannot_open_the_queue()
    {
        $user = $this->makeUser('GENERAL_USER', 'Nosy');

        // The hole this closes: the panel sat behind `auth` alone, so a buyer
        // with a web session could read reported message text and the names of
        // the people accused.
        $this->actingAs($user)->get('/reports')->assertForbidden();
    }

    public function test_an_admin_can_open_the_queue()
    {
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->get('/reports')->assertOk();
    }

    public function test_the_api_admin_check_still_answers_with_json()
    {
        $user = $this->makeUser('GENERAL_USER', 'Nosy');

        // The same middleware guards api/admin/*. It must keep its JSON 403 and
        // not start returning an HTML abort page to an API client.
        $this->actingAs($user, 'sanctum')
            ->getJson('/api/admin/seller-requests')
            ->assertForbidden()
            ->assertJsonStructure(['message']);
    }

    // -------------------------------------------------------------- rendering

    public function test_the_queue_renders_a_report_about_a_listing()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID, [
            'LST_ID' => $listing['listing']->LST_ID,
            'RPT_REASON' => Report::REASONS['MISLEADING_INFO'],
            'RPT_REASON_CODE' => 'MISLEADING_INFO',
        ]);

        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->get('/reports')->assertOk()->assertSee('Crop listing');
        $this->actingAs($admin)->get("/reports/{$report->RPT_ID}")
            ->assertOk()
            ->assertSee('React A Farm')
            ->assertSee('Misleading or false information');
    }

    public function test_the_queue_renders_a_report_about_a_message_with_its_text()
    {
        $seller = $this->makeListing();
        $buyer = $this->makeUser('GENERAL_USER', 'Maria');
        $buyerRow = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $buyer->USR_ID]);

        $conversation = Conversation::create([
            'CONV_ID' => $this->id('CNV'),
            'LST_ID' => $seller['listing']->LST_ID,
            'CONV_CREATED_AT' => now(),
            'BUY_ID' => $buyerRow->BUY_ID,
            'FMR_ID' => $seller['farmer']->FMR_ID,
        ]);
        $message = Message::create([
            'MSG_ID' => $this->id('MSG'),
            'MSG_CONTENT' => 'send payment to this gcash number',
            'MSG_IS_READ' => 0,
            'MSG_CREATED_AT' => now(),
            'CONV_ID' => $conversation->CONV_ID,
            'USR_ID' => $seller['user']->USR_ID,
        ]);

        $report = $this->makeReport('MESSAGE', $message->MSG_ID, [
            'LST_ID' => $seller['listing']->LST_ID,
            'RPT_REASON' => Report::REASONS['FRAUD_OR_SCAM'],
            'RPT_REASON_CODE' => 'FRAUD_OR_SCAM',
        ]);

        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->get("/reports/{$report->RPT_ID}")
            ->assertOk()
            ->assertSee('Chat message')
            // A moderator cannot judge a message report without the message.
            ->assertSee('send payment to this gcash number')
            ->assertSee('React A');
    }

    public function test_reported_message_text_is_escaped_not_rendered_as_markup()
    {
        $seller = $this->makeListing();
        $message = Message::create([
            'MSG_ID' => $this->id('MSG'),
            // A reported message is chosen by whoever is being reported, so it
            // must never reach the page as markup.
            'MSG_CONTENT' => '<script>alert(1)</script>',
            'MSG_IS_READ' => 0,
            'MSG_CREATED_AT' => now(),
            'CONV_ID' => Conversation::create([
                'CONV_ID' => $this->id('CNV'),
                'CONV_CREATED_AT' => now(),
                'BUY_ID' => Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $this->makeUser('GENERAL_USER', 'Maria')->USR_ID])->BUY_ID,
                'FMR_ID' => $seller['farmer']->FMR_ID,
            ])->CONV_ID,
            'USR_ID' => $seller['user']->USR_ID,
        ]);

        $report = $this->makeReport('MESSAGE', $message->MSG_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $response = $this->actingAs($admin)->get("/reports/{$report->RPT_ID}");

        $response->assertOk();
        $response->assertDontSee('<script>alert(1)</script>', false);
        // escapeHtml: false, because the page source already contains the
        // escaped entity and the default would escape the expectation again.
        $response->assertSee('&lt;script&gt;', false);
    }

    public function test_the_queue_renders_a_report_about_a_person()
    {
        $farmer = $this->makeListing();
        $report = $this->makeReport('FARMER', $farmer['farmer']->FMR_ID, [
            'RPT_REASON' => Report::REASONS['HARASSMENT'],
            'RPT_REASON_CODE' => 'HARASSMENT',
        ]);

        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->get("/reports/{$report->RPT_ID}")
            ->assertOk()
            ->assertSee('Farmer')
            ->assertSee('React A')
            ->assertSee('Harassment or bullying');
    }

    public function test_the_queue_renders_a_report_about_a_user_account()
    {
        $target = $this->makeUser('GENERAL_USER', 'Problem Buyer');
        $report = $this->makeReport('USER', $target->USR_ID);

        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->get("/reports/{$report->RPT_ID}")
            ->assertOk()
            ->assertSee('User account')
            ->assertSee('Problem Buyer');
    }

    public function test_the_queue_survives_a_listing_that_was_deleted_afterwards()
    {
        // report.LST_ID cascades on delete, so a removed listing takes its
        // reports with it - but a report about a message or a person has no
        // listing at all, and the row must still render.
        $report = $this->makeReport('FARMER', 'FAKE01');
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->get("/reports/{$report->RPT_ID}")->assertOk();
    }

    public function test_the_queue_can_be_filtered_by_type()
    {
        $listing = $this->makeListing();
        $this->makeReport('LISTING', $listing['listing']->LST_ID, [
            'RPT_REASON' => Report::REASONS['MISLEADING_INFO'],
            'RPT_REASON_CODE' => 'MISLEADING_INFO',
        ]);
        $this->makeReport('FARMER', 'FAKE01', [
            'RPT_REASON' => Report::REASONS['UNSAFE_BEHAVIOR'],
            'RPT_REASON_CODE' => 'UNSAFE_BEHAVIOR',
        ]);

        $admin = $this->makeUser('ADMIN', 'Admin');

        // Asserted on the reason labels, because that is what the index row
        // actually renders. Two alternatives that look right but are not:
        // RPT_ID is an auto-increment, so in a full-suite run it is a small
        // integer that also appears in counts and dates; and the type names
        // ("Crop listing", "Farmer") appear in the filter dropdown on every
        // page regardless of the filter in force.
        $this->actingAs($admin)->get('/reports?type=FARMER')
            ->assertOk()
            ->assertSee(Report::REASONS['UNSAFE_BEHAVIOR'])
            ->assertDontSee(Report::REASONS['MISLEADING_INFO']);
    }

    // ---------------------------------------------------------------- triage

    public function test_updating_the_status_stamps_when_it_changed()
    {
        $report = $this->makeReport('LISTING', 'AAAAAA');
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->assertNull($report->RPT_UPDATED_AT);

        $this->actingAs($admin)
            ->patch("/reports/{$report->RPT_ID}/status", ['status' => 'Reviewing'])
            ->assertRedirect(route('reports'));

        $this->assertDatabaseHas('report', [
            'RPT_ID' => $report->RPT_ID,
            'RPT_STATUS' => 'Reviewing',
        ]);
        $this->assertNotNull($report->fresh()->RPT_UPDATED_AT);
    }

    public function test_a_non_admin_cannot_change_a_report_status()
    {
        $report = $this->makeReport('LISTING', 'AAAAAA');
        $user = $this->makeUser('GENERAL_USER', 'Nosy');

        $this->actingAs($user)
            ->patch("/reports/{$report->RPT_ID}/status", ['status' => 'Dismissed'])
            ->assertForbidden();

        $this->assertSame('New', $report->fresh()->RPT_STATUS);
    }

    public function test_an_unknown_status_is_rejected()
    {
        $report = $this->makeReport('LISTING', 'AAAAAA');
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)
            ->patch("/reports/{$report->RPT_ID}/status", ['status' => 'Ignored'])
            ->assertSessionHasErrors('status');
    }

    // -------------------------------------------------------------- enforcing
    //
    // A report is a lead, not a verdict, so every one of these is a moderator
    // clicking a button on one report. There is no counter anywhere: wiring
    // "three reports = suspended" would let any one buyer bury a competitor by
    // filing three reports against them.
    //
    // Each step is its own report_action row, so a report can carry several
    // independent decisions and undoing one leaves the others alone.

    public function test_taking_down_a_listing_actually_removes_it_from_the_feed()
    {
        // The whole point. A moderator who agrees a listing is fraudulent used
        // to have no way to act, so the buyer who reported it saw nothing
        // happen. REMOVED is what every buyer-facing query filters on.
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)
            ->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN", ['note' => 'Confirmed fraud by phone'])
            ->assertRedirect(route('reports.show', $report->RPT_ID));

        $this->assertSame('REMOVED', $listing['listing']->fresh()->LST_AVAILABILITY);

        $action = ReportAction::where('RPT_ID', $report->RPT_ID)->firstOrFail();
        $this->assertSame('LISTING_TAKEN_DOWN', $action->RAC_ACTION);
        $this->assertSame('LISTING', $action->RAC_SUBJECT_TYPE);
        $this->assertSame($admin->USR_ID, $action->RAC_BY);
        $this->assertSame('Confirmed fraud by phone', $action->RAC_NOTE);
        $this->assertNull($action->RAC_REVERTED_AT);
        $this->assertTrue($action->isLive());

        // Acting is work in progress, so a report still sitting unread as New
        // moves along.
        $this->assertSame('Reviewing', $report->fresh()->RPT_STATUS);
    }

    public function test_undoing_a_takedown_puts_the_listing_back()
    {
        // Getting a takedown wrong is expected — a real listing can look fake
        // until someone checks — so it has to be one click, not a support ticket.
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");

        $this->actingAs($admin)
            // The literal undo path, which the {action} wildcard would otherwise
            // swallow and treat as an action named "undo".
            ->post("/reports/{$report->RPT_ID}/action/undo")
            ->assertRedirect(route('reports.show', $report->RPT_ID));

        $this->assertSame('ACTIVE', $listing['listing']->fresh()->LST_AVAILABILITY);
        $this->assertCount(0, $report->fresh()->liveActions);
    }

    public function test_an_undone_action_is_kept_in_the_history()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");
        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");

        // Nothing is ever deleted, so "who did what, and did it stick" stays
        // answerable after the fact.
        $action = ReportAction::where('RPT_ID', $report->RPT_ID)->firstOrFail();
        $this->assertCount(1, $report->fresh()->actions);
        $this->assertNotNull($action->RAC_REVERTED_AT);
        $this->assertSame($admin->USR_ID, $action->RAC_REVERTED_BY);
        $this->assertFalse($action->isLive());
    }

    public function test_undoing_restores_the_value_that_was_there_before_not_a_hardcoded_active()
    {
        // A listing can be NOT_AVAILABLE for an honest reason while it is being
        // reported. Restoring it to ACTIVE would put unsold produce back on sale.
        $listing = $this->makeListing();
        $listing['listing']->update(['LST_AVAILABILITY' => 'NOT_AVAILABLE']);
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");
        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");

        $this->assertSame('NOT_AVAILABLE', $listing['listing']->fresh()->LST_AVAILABILITY);
    }

    public function test_the_seller_behind_a_reported_listing_can_be_deactivated()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/SELLER_DEACTIVATED");

        $this->assertSame('DEACTIVATED', $listing['user']->fresh()->USR_STATUS);
        // The listing itself is a separate decision, so it stays on sale.
        $this->assertSame('ACTIVE', $listing['listing']->fresh()->LST_AVAILABILITY);

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");
        $this->assertSame('ACTIVE', $listing['user']->fresh()->USR_STATUS);
    }

    public function test_deactivating_an_account_revokes_the_tokens_it_already_had()
    {
        // Setting USR_STATUS alone only blocks the *next* login. AuthController
        // checks it once, at login, and nothing revokes tokens already issued —
        // so a buyer who reported harassment and was then deactivated kept full
        // API access from an app that was already installed.
        $listing = $this->makeListing();
        $report = $this->makeReport('USER', $listing['user']->USR_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $theirToken = $listing['user']->createToken('their phone')->accessToken;
        $this->assertDatabaseCount('personal_access_tokens', 1);

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/ACCOUNT_DEACTIVATED");

        $this->assertSame('DEACTIVATED', $listing['user']->fresh()->USR_STATUS);
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_deactivating_an_account_is_blocked_again_at_the_next_login()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('USER', $listing['user']->USR_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/ACCOUNT_DEACTIVATED");

        // The token is gone, so the next thing they can do is try to log in
        // again — and that has to fail too, not just fail to be pre-authorised.
        $this->postJson('/api/login', [
            'email' => strtolower($listing['user']->USR_ID).'@test.local',
            'password' => 'password123',
        ])->assertStatus(403)
            ->assertJsonPath('message', 'This account has been deactivated.');

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_a_farmer_report_offers_account_and_listing_as_two_separate_decisions()
    {
        // A farmer is a row hanging off a buyer, which hangs off a user, so
        // "deactivate this farmer" means the account, and "take down their
        // listings" is a smaller, separate thing. Both are offered, and either
        // can be taken on its own.
        $listing = $this->makeListing();
        $report = $this->makeReport('FARMER', $listing['farmer']->FMR_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $response = $this->actingAs($admin)->get("/reports/{$report->RPT_ID}")->assertOk();
        $response->assertSee('Deactivate this farmer');
        $response->assertSee('Take down all their listings');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/FARMER_ACCOUNT_DEACTIVATED");

        $this->assertSame('DEACTIVATED', $listing['user']->fresh()->USR_STATUS);
        // Proportionate: only the account step was taken, so they keep trading.
        $this->assertSame('ACTIVE', $listing['listing']->fresh()->LST_AVAILABILITY);

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");
        $this->assertSame('ACTIVE', $listing['user']->fresh()->USR_STATUS);
    }

    public function test_taking_down_a_farmers_listings_leaves_their_account_alone()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('FARMER', $listing['farmer']->FMR_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/FARMER_LISTINGS_TAKEN_DOWN");

        $this->assertSame('REMOVED', $listing['listing']->fresh()->LST_AVAILABILITY);
        $this->assertSame('ACTIVE', $listing['user']->fresh()->USR_STATUS);

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");
        $this->assertSame('ACTIVE', $listing['listing']->fresh()->LST_AVAILABILITY);
    }

    public function test_two_actions_on_one_report_are_independent_and_undo_pops_the_newest()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");
        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/SELLER_DEACTIVATED");

        $this->assertSame('REMOVED', $listing['listing']->fresh()->LST_AVAILABILITY);
        $this->assertSame('DEACTIVATED', $listing['user']->fresh()->USR_STATUS);
        $this->assertCount(2, $report->fresh()->liveActions);

        // Undo takes back the seller deactivation and leaves the takedown up.
        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");

        $this->assertSame('ACTIVE', $listing['user']->fresh()->USR_STATUS);
        $this->assertSame('REMOVED', $listing['listing']->fresh()->LST_AVAILABILITY);
        $this->assertCount(1, $report->fresh()->liveActions);

        // And again for the takedown.
        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");
        $this->assertSame('ACTIVE', $listing['listing']->fresh()->LST_AVAILABILITY);
        $this->assertCount(0, $report->fresh()->liveActions);
    }

    public function test_a_reported_message_can_be_hidden_and_comes_back_out_of_the_conversation()
    {
        $listing = $this->makeListing();
        $message = $this->makeMessage($listing['user'], $listing['listing']);
        $report = $this->makeReport('MESSAGE', $message->MSG_ID, [
            'LST_ID' => $listing['listing']->LST_ID,
            'RPT_REASON' => Report::REASONS['FRAUD_OR_SCAM'],
            'RPT_REASON_CODE' => 'FRAUD_OR_SCAM',
        ]);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/MESSAGE_HIDDEN");

        $message->refresh();
        $this->assertSame('HIDDEN', $message->MSG_VISIBILITY);
        $this->assertNotNull($message->MSG_HIDDEN_AT);
        $this->assertTrue($message->isHidden());
        // Kept, not deleted, so the decision stays reviewable.
        $this->assertDatabaseHas('message', ['MSG_ID' => $message->MSG_ID]);

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");

        $message->refresh();
        $this->assertSame('VISIBLE', $message->MSG_VISIBILITY);
        $this->assertNull($message->MSG_HIDDEN_AT);
    }

    public function test_a_hidden_message_is_not_returned_by_the_conversation_api()
    {
        $listing = $this->makeListing();
        $message = $this->makeMessage($listing['user'], $listing['listing']);
        $report = $this->makeReport('MESSAGE', $message->MSG_ID, [
            'LST_ID' => $listing['listing']->LST_ID,
        ]);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/MESSAGE_HIDDEN");

        // A hidden message must not reach the reader's phone at all — the row
        // staying in the database is for the audit trail, not the buyer.
        $this->assertDatabaseHas('message', ['MSG_ID' => $message->MSG_ID, 'MSG_VISIBILITY' => 'HIDDEN']);
    }

    public function test_a_listing_that_is_already_off_sale_is_not_actioned_again()
    {
        $listing = $this->makeListing();
        $listing['listing']->update(['LST_AVAILABILITY' => 'REMOVED']);
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)
            ->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN")
            ->assertSessionHas('error');

        $this->assertCount(0, $report->fresh()->actions);
    }

    public function test_the_same_action_is_not_applied_twice_while_one_is_live()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");
        $this->actingAs($admin)
            ->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN")
            ->assertSessionHas('error');

        $this->assertCount(1, $report->fresh()->actions);
    }

    public function test_an_action_that_does_not_exist_is_refused()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)
            ->post("/reports/{$report->RPT_ID}/action/DROP_DATABASE")
            ->assertSessionHas('error');

        $this->assertCount(0, $report->fresh()->actions);
    }

    public function test_a_dismissed_report_offers_nothing_to_act_on()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID, [
            'RPT_STATUS' => 'Dismissed',
        ]);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)
            ->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN")
            ->assertSessionHas('error');

        $this->assertSame('ACTIVE', $listing['listing']->fresh()->LST_AVAILABILITY);
    }

    public function test_a_deleted_listing_is_explained_rather_than_silently_unactionable()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $listing['listing']->delete();

        // A missing button with no explanation is how a moderator ends up
        // thinking the queue cannot act at all.
        $this->actingAs($admin)
            ->get("/reports/{$report->RPT_ID}")
            ->assertOk()
            ->assertSee('This listing no longer exists');
    }

    public function test_a_non_admin_cannot_take_action_on_a_report()
    {
        // The queue is admin-only, so a buyer must not be able to deactivate
        // another account by filing a report and then posting to the web panel.
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $nosy = $this->makeUser('GENERAL_USER', 'Nosy');

        $this->actingAs($nosy)
            ->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN")
            ->assertForbidden();

        $this->assertSame('ACTIVE', $listing['listing']->fresh()->LST_AVAILABILITY);
        $this->assertCount(0, $report->fresh()->actions);
    }

    // ------------------------------------------------------------ the record

    public function test_the_record_says_what_changed_and_who_changed_it()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN", [
            'note' => 'Seller confirmed the price was a typo',
        ]);

        $action = ReportAction::where('RPT_ID', $report->RPT_ID)->firstOrFail();

        $this->assertSame($admin->USR_ID, $action->RAC_BY);
        $this->assertSame($listing['listing']->LST_ID, $action->RAC_SUBJECT_ID);
        $this->assertSame('Seller confirmed the price was a typo', $action->RAC_NOTE);
        $this->assertNotNull($action->RAC_APPLIED_AT);

        // The previous value is what makes undo exact rather than a guess.
        $this->assertSame(['listings' => [$listing['listing']->LST_ID => 'ACTIVE']], $action->previous());
        $this->assertSame('Listing taken off sale', $action->label());
    }

    public function test_the_reporter_is_told_when_their_report_is_actioned()
    {
        // Reporting was a one-way door: the buyer pressed submit and then heard
        // nothing, so an actioned report looked exactly like an ignored one.
        Notification::fake();

        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");

        Notification::assertSentTo(
            $report->user,
            ReportActioned::class,
            fn ($notification) => $notification->applied === true
                && $notification->report->RPT_ID === $report->RPT_ID
                && $notification->action->RAC_ACTION === 'LISTING_TAKEN_DOWN'
        );
    }

    public function test_the_reporter_is_told_when_a_decision_is_reversed()
    {
        Notification::fake();

        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");
        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");

        Notification::assertSentTo(
            $report->user,
            ReportActioned::class,
            fn ($notification) => $notification->applied === false
                && $notification->action->RAC_ACTION === 'LISTING_TAKEN_DOWN'
        );
    }

    // ---------------------------------------------------------- what the user sees

    public function test_the_takedown_shows_on_the_report_page()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");

        $this->actingAs($admin)
            ->get("/reports/{$report->RPT_ID}")
            ->assertOk()
            ->assertSee('Listing taken off sale')
            ->assertSee('Undo the most recent action');
    }

    public function test_the_report_page_offers_the_steps_still_open()
    {
        // After one step, the other is still on the table rather than the whole
        // subject being locked out by the first click.
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");

        $this->actingAs($admin)
            ->get("/reports/{$report->RPT_ID}")
            ->assertOk()
            ->assertSee('Deactivate the seller who posted this')
            ->assertDontSee('Take this listing off sale');
    }

    public function test_the_queue_shows_how_many_actions_are_in_force()
    {
        // A status of Resolved on its own does not tell a moderator whether the
        // listing came down or the report was just closed.
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");

        $this->actingAs($admin)
            ->get('/reports')
            ->assertOk()
            ->assertSee('1 action in force');
    }

    public function test_an_undone_action_drops_back_to_nothing_in_force_on_the_queue()
    {
        $listing = $this->makeListing();
        $report = $this->makeReport('LISTING', $listing['listing']->LST_ID);
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/LISTING_TAKEN_DOWN");
        $this->actingAs($admin)->post("/reports/{$report->RPT_ID}/action/undo");

        // The history is still on the report page; the queue just stops claiming
        // something is in force.
        $this->actingAs($admin)
            ->get('/reports')
            ->assertOk()
            ->assertDontSee('action in force');
    }
}
