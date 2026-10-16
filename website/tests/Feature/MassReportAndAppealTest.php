<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Report;
use App\Models\ReportAction;
use App\Models\ReviewRequest;
use App\Models\User;
use App\Services\MassReportService;
use App\Services\ModerationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The two features this round added on top of the existing report queue:
 *
 *  1. Mass-report flagging — a target that reaches the threshold of distinct
 *     reporters on open reports gets RPT_FLAGGED_AT so the admin queue lights
 *     up. It only ever sets a timestamp; nothing is taken down automatically.
 *
 *  2. Appeals — a listing or account removed by an admin (which is exactly a
 *     REMOVED/DEACTIVATED row with a takedown reason) can be re-evaluated.
 *     Approving restores the target and dismisses the open reports against it;
 *     denying keeps everything and is final until a new takedown.
 */
class MassReportAndAppealTest extends TestCase
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
            'CAT' => 'crop_category',
        ][$prefix];

        $column = "{$prefix}_ID";

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
            'RPT_ID' => Report::newId(),
            'LST_ID' => null,
            'USR_ID' => $this->makeUser('GENERAL_USER', 'Reporter')->USR_ID,
            'RPT_REASON' => Report::REASONS['OTHER'],
            'RPT_REASON_CODE' => 'OTHER',
            'RPT_TARGET_TYPE' => $type,
            'RPT_TARGET_ID' => $targetId,
        ], $extra));
    }

    /**
     * Put a listing into the takedown state an admin action produces.
     *
     * Setting the fields directly keeps these tests focused on what happens
     * next (flagging, appealing, restoring) rather than on the queue that
     * normally performs the removal.
     */
    private function takeDownListing(Listing $listing, string $reason = 'Fake listing'): void
    {
        $listing->forceFill([
            'LST_AVAILABILITY' => 'REMOVED',
            'LST_TAKEDOWN_REASON' => $reason,
            'LST_TAKEDOWN_AT' => now(),
            'LST_HIDDEN_BY_TAKEDOWN' => true,
        ])->save();
    }

    // ------------------------------------------------------------- flagging

    public function test_a_tenth_distinct_reporter_flags_the_target()
    {
        $listing = $this->makeListing();
        $target = $listing['listing']->LST_ID;
        $service = app(MassReportService::class);

        // Nine distinct voices is still below the line: close enough to read
        // as a busy target, not yet a wave.
        for ($i = 0; $i < 9; $i++) {
            $service->flagIfThresholdReached(
                $this->makeReport('LISTING', $target, ['LST_ID' => $target])
            );
        }

        $this->assertSame(
            0,
            Report::where('RPT_TARGET_TYPE', 'LISTING')
                ->where('RPT_TARGET_ID', $target)
                ->whereNotNull('RPT_FLAGGED_AT')
                ->count()
        );

        $service->flagIfThresholdReached(
            $this->makeReport('LISTING', $target, ['LST_ID' => $target])
        );

        // The flag is stamped on every open row for the target, so whichever
        // one a moderator opens first shows it.
        $this->assertSame(
            10,
            Report::where('RPT_TARGET_TYPE', 'LISTING')
                ->where('RPT_TARGET_ID', $target)
                ->whereNotNull('RPT_FLAGGED_AT')
                ->count()
        );
    }

    public function test_one_reporter_cannot_flag_a_target_on_their_own()
    {
        $listing = $this->makeListing();
        $target = $listing['listing']->LST_ID;
        $reporter = $this->makeUser('GENERAL_USER', 'Persistent')->USR_ID;
        $service = app(MassReportService::class);

        // Ten filings, one person. Distinct reporters — not row count — is
        // what the threshold counts, so this never lights up.
        for ($i = 0; $i < 10; $i++) {
            $service->flagIfThresholdReached(
                $this->makeReport('LISTING', $target, ['LST_ID' => $target, 'USR_ID' => $reporter])
            );
        }

        $this->assertSame(
            0,
            Report::where('RPT_TARGET_TYPE', 'LISTING')
                ->where('RPT_TARGET_ID', $target)
                ->whereNotNull('RPT_FLAGGED_AT')
                ->count()
        );
    }

    public function test_resolving_the_reports_clears_the_flag()
    {
        $listing = $this->makeListing();
        $target = $listing['listing']->LST_ID;
        $service = app(MassReportService::class);

        for ($i = 0; $i < 10; $i++) {
            $service->flagIfThresholdReached(
                $this->makeReport('LISTING', $target, ['LST_ID' => $target])
            );
        }

        $this->assertGreaterThan(0, Report::open()->whereNotNull('RPT_FLAGGED_AT')->count());

        app(ModerationService::class)->finishOpenReports(
            [[Report::TARGET_LISTING, $target]],
            'Resolved'
        );

        // A finished queue should not keep a target lit up — otherwise a new
        // wave could never re-flag it.
        $this->assertSame(0, Report::whereNotNull('RPT_FLAGGED_AT')->count());
    }

    public function test_acting_on_a_target_from_the_alert_page_resolves_the_whole_cluster()
    {
        $data = $this->makeListing();
        $listing = $data['listing'];
        $admin = $this->makeUser('ADMIN', 'Admin');
        $service = app(MassReportService::class);

        // Ten distinct reporters put the listing over the line.
        for ($i = 0; $i < 10; $i++) {
            $service->flagIfThresholdReached(
                $this->makeReport('LISTING', $listing->LST_ID, ['LST_ID' => $listing->LST_ID])
            );
        }

        $this->assertSame(10, Report::open()->whereNotNull('RPT_FLAGGED_AT')->count());

        // One decision from the target page, not ten from the queue.
        $this->actingAs($admin)
            ->post("/reports/flagged/LISTING/{$listing->LST_ID}/action/LISTING_TAKEN_DOWN", [
                'note' => 'Fake listing',
            ])
            ->assertRedirect('/reports/flagged');

        // The subject actually changed, carrying the reason the owner will see...
        $listing->refresh();
        $this->assertSame('REMOVED', $listing->LST_AVAILABILITY);
        $this->assertSame('Fake listing', $listing->LST_TAKEDOWN_REASON);

        // ...and every report behind the alert is closed, not left hanging.
        $this->assertSame(0, Report::open()
            ->where('RPT_TARGET_TYPE', Report::TARGET_LISTING)
            ->where('RPT_TARGET_ID', $listing->LST_ID)
            ->count());
        $this->assertSame(0, Report::whereNotNull('RPT_FLAGGED_AT')->count());

        // The action is on the audit trail, hung on a real report.
        $this->assertSame(1, ReportAction::where('RAC_ACTION', 'LISTING_TAKEN_DOWN')
            ->where('RAC_SUBJECT_ID', $listing->LST_ID)
            ->where('RAC_BY', $admin->USR_ID)
            ->count());

        // Every reporter behind the closed reports is told, not just the one the
        // action happened to hang on: a report that silently changes status is
        // what makes reporting feel like a void.
        $reporterIds = Report::where('RPT_TARGET_TYPE', Report::TARGET_LISTING)
            ->where('RPT_TARGET_ID', $listing->LST_ID)
            ->pluck('USR_ID')
            ->all();

        $this->assertCount(10, array_unique($reporterIds));

        foreach ($reporterIds as $usrId) {
            $this->assertSame(1, DB::table('notification')
                ->where('NOTIF_TYPE', 'REPORT_UPDATE')
                ->where('USR_ID', $usrId)
                ->count(), "reporter {$usrId} should have exactly one update");
        }
    }

    public function test_undoing_a_target_action_reopens_the_reports_it_closed()
    {
        $data = $this->makeListing();
        $listing = $data['listing'];
        $admin = $this->makeUser('ADMIN', 'Admin');
        $service = app(MassReportService::class);

        // Ten distinct reporters, then one decision from the alert page.
        for ($i = 0; $i < 10; $i++) {
            $service->flagIfThresholdReached(
                $this->makeReport('LISTING', $listing->LST_ID, ['LST_ID' => $listing->LST_ID])
            );
        }

        $this->actingAs($admin)
            ->post("/reports/flagged/LISTING/{$listing->LST_ID}/action/LISTING_TAKEN_DOWN", [
                'note' => 'Fake listing',
            ])
            ->assertRedirect('/reports/flagged');

        $this->assertSame(0, Report::open()->count());

        // The action lives on one report. Undoing it has to bring the whole
        // cluster back, not just the row it was hung on, or the queue would
        // read as quieter than the takedown it is undoing.
        $anchor = ReportAction::where('RAC_ACTION', 'LISTING_TAKEN_DOWN')
            ->where('RAC_SUBJECT_ID', $listing->LST_ID)
            ->firstOrFail();

        $this->actingAs($admin)
            ->post("/reports/{$anchor->RPT_ID}/action/undo")
            ->assertRedirect("/reports/{$anchor->RPT_ID}");

        // Subject put back...
        $this->assertSame('ACTIVE', $listing->refresh()->LST_AVAILABILITY);

        // ...and all ten reports are open again, back over the line and flagged,
        // so the wave is visible instead of silently resolved.
        $this->assertSame(10, Report::open()
            ->where('RPT_TARGET_TYPE', Report::TARGET_LISTING)
            ->where('RPT_TARGET_ID', $listing->LST_ID)
            ->count());
        $this->assertSame(10, Report::open()->whereNotNull('RPT_FLAGGED_AT')->count());
    }

    public function test_an_approved_appeal_tells_the_reporters_their_report_was_dismissed()
    {
        $data = $this->makeListing();
        $listing = $data['listing'];
        $admin = $this->makeUser('ADMIN', 'Admin');

        // A report still open when the listing is taken down.
        $report = $this->makeReport('LISTING', $listing->LST_ID, ['LST_ID' => $listing->LST_ID]);
        $this->takeDownListing($listing);

        $appealId = $this->actingAs($data['user'], 'sanctum')
            ->postJson("/api/listings/{$listing->LST_ID}/appeal", ['reason' => 'It is mine'])
            ->assertStatus(201)
            ->json('appeal_id');

        $this->actingAs($admin)->post("/appeals/{$appealId}/approve")->assertRedirect('/appeals');

        // The owner hears the verdict through the appeal notification; the
        // reporter is a different audience and hears their own report was
        // dismissed, because the takedown it reported was wrong.
        $row = DB::table('notification')
            ->where('NOTIF_TYPE', 'REPORT_UPDATE')
            ->where('USR_ID', $report->USR_ID)
            ->first();

        $this->assertNotNull($row, 'the reporter should have been told their report was dismissed');
        $this->assertSame('Your report was dismissed', $row->NOTIF_TITLE);
        $this->assertSame($report->RPT_ID, $row->NOTIF_REF_ID);
    }

    public function test_a_denied_appeal_tells_the_reporters_their_report_was_resolved()
    {
        $data = $this->makeListing();
        $listing = $data['listing'];
        $admin = $this->makeUser('ADMIN', 'Admin');

        $report = $this->makeReport('LISTING', $listing->LST_ID, ['LST_ID' => $listing->LST_ID]);
        $this->takeDownListing($listing);

        $appealId = $this->actingAs($data['user'], 'sanctum')
            ->postJson("/api/listings/{$listing->LST_ID}/appeal", ['reason' => 'Please restore'])
            ->assertStatus(201)
            ->json('appeal_id');

        $this->actingAs($admin)->post("/appeals/{$appealId}/deny")->assertRedirect('/appeals');

        // Denied means the takedown stands, so the report is resolved rather
        // than dismissed and the reporter is told so.
        $row = DB::table('notification')
            ->where('NOTIF_TYPE', 'REPORT_UPDATE')
            ->where('USR_ID', $report->USR_ID)
            ->first();

        $this->assertNotNull($row, 'the reporter should have been told their report was resolved');
        $this->assertSame('Your report was resolved', $row->NOTIF_TITLE);
    }

    // ------------------------------------------------------------- appeals

    public function test_an_admin_can_open_the_appeals_queue()
    {
        $admin = $this->makeUser('ADMIN', 'Admin');

        // A queue nobody can render is a queue nobody can decide, and the new
        // nav link points straight at it.
        $this->actingAs($admin)->get('/appeals')->assertOk();
    }

    public function test_a_non_admin_cannot_open_the_appeals_queue()
    {
        $user = $this->makeUser('GENERAL_USER', 'Nosy');

        $this->actingAs($user)->get('/appeals')->assertForbidden();
    }

    public function test_the_appeal_detail_page_renders()
    {
        $data = $this->makeListing();
        $this->takeDownListing($data['listing']);

        $appealId = $this->actingAs($data['user'], 'sanctum')
            ->postJson("/api/listings/{$data['listing']->LST_ID}/appeal", ['reason' => 'It is mine'])
            ->assertStatus(201)
            ->json('appeal_id');

        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->actingAs($admin)->get("/appeals/{$appealId}")->assertOk()->assertSee('It is mine');
    }

    public function test_a_taken_down_listing_can_be_restored_by_appeal()
    {
        $data = $this->makeListing();
        $listing = $data['listing'];
        $admin = $this->makeUser('ADMIN', 'Admin');

        // One report against it, still open when the listing goes down.
        $this->makeReport('LISTING', $listing->LST_ID, ['LST_ID' => $listing->LST_ID]);
        $this->takeDownListing($listing);

        $response = $this->actingAs($data['user'], 'sanctum')
            ->postJson("/api/listings/{$listing->LST_ID}/appeal", [
                'reason' => 'The crop photo is mine, it was not misleading.',
            ]);

        $response->assertStatus(201);
        $appealId = $response->json('appeal_id');

        $this->actingAs($admin)
            ->post("/appeals/{$appealId}/approve")
            ->assertRedirect('/appeals');

        $listing->refresh();
        $this->assertTrue($listing->LST_AVAILABILITY === 'ACTIVE');
        $this->assertNull($listing->LST_TAKEDOWN_REASON);
        $this->assertFalse($listing->isTakenDown());

        // The reports that put the listing down are closed out — and as
        // Dismissed, because the takedown was wrong.
        $this->assertSame(
            'Dismissed',
            Report::where('RPT_TARGET_TYPE', Report::TARGET_LISTING)
                ->where('RPT_TARGET_ID', $listing->LST_ID)
                ->value('RPT_STATUS')
        );

        $this->assertSame(
            ReviewRequest::STATUS_APPROVED,
            ReviewRequest::where('RRQ_ID', $appealId)->value('RRQ_STATUS')
        );
    }

    public function test_a_denied_appeal_is_final_until_a_new_takedown()
    {
        $data = $this->makeListing();
        $listing = $data['listing'];
        $admin = $this->makeUser('ADMIN', 'Admin');

        $this->takeDownListing($listing);

        $first = $this->actingAs($data['user'], 'sanctum')
            ->postJson("/api/listings/{$listing->LST_ID}/appeal", ['reason' => 'Please restore'])
            ->assertStatus(201)
            ->json('appeal_id');

        $this->actingAs($admin)->post("/appeals/{$first}/deny")->assertRedirect('/appeals');

        // Same takedown, no new removal: the denial holds and a second request
        // is refused rather than opening an endless loop of re-asks.
        $this->actingAs($data['user'], 'sanctum')
            ->postJson("/api/listings/{$listing->LST_ID}/appeal", ['reason' => 'Second try'])
            ->assertStatus(422);

        // A genuinely new takedown restarts the clock.
        $listing->forceFill(['LST_TAKEDOWN_AT' => now()->addSecond()])->save();

        $this->actingAs($data['user'], 'sanctum')
            ->postJson("/api/listings/{$listing->LST_ID}/appeal", ['reason' => 'New removal, new ask'])
            ->assertStatus(201);
    }

    public function test_a_listing_the_farmer_deleted_cannot_be_appealed()
    {
        $data = $this->makeListing();
        $listing = $data['listing'];

        // The farmer removed it themselves: REMOVED but no takedown reason,
        // which is precisely the case with no re-evaluation path.
        $listing->forceFill(['LST_AVAILABILITY' => 'REMOVED'])->save();

        $this->actingAs($data['user'], 'sanctum')
            ->postJson("/api/listings/{$listing->LST_ID}/appeal", ['reason' => 'Bring it back'])
            ->assertStatus(403)
            ->assertJsonPath('message', 'This listing is not appealable.');
    }

    public function test_a_taken_down_account_can_be_appealed_and_restored()
    {
        $data = $this->makeListing();
        $user = $data['user'];
        $admin = $this->makeUser('ADMIN', 'Admin');

        // One listing we hid as part of the takedown, one the farmer had
        // already deleted for their own reasons.
        $deleted = Listing::create([
            'LST_ID' => $this->id('LST'),
            'LST_CROP_ICON' => 'Taro',
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'REMOVED',
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $data['farmer']->FMR_ID,
            'FRM_ID' => $data['farm']->FRM_ID,
            'CAT_ID' => $this->categoryId(),
        ]);

        $user->forceFill([
            'USR_STATUS' => 'DEACTIVATED',
            'USR_TAKEDOWN_REASON' => 'Repeated fake listings',
            'USR_TAKEDOWN_AT' => now(),
            'USR_HIDDEN_BY_TAKEDOWN' => true,
        ])->save();

        $this->takeDownListing($data['listing'], 'Repeated fake listings');

        $response = $this->postJson('/api/appeals/account', [
            'email' => $user->USR_EMAIL,
            'password' => 'password123',
            'reason' => 'I have removed the offending listings.',
        ])->assertStatus(201);

        $appealId = $response->json('appeal_id');

        $this->actingAs($admin)->post("/appeals/{$appealId}/approve")->assertRedirect('/appeals');

        $user->refresh();
        $this->assertSame('ACTIVE', $user->USR_STATUS);
        $this->assertNull($user->USR_TAKEDOWN_REASON);

        // Only the listings the takedown hid come back.
        $this->assertSame('ACTIVE', $data['listing']->refresh()->LST_AVAILABILITY);
        $this->assertSame('REMOVED', $deleted->refresh()->LST_AVAILABILITY);
    }

    public function test_a_plain_deactivation_is_not_appealable()
    {
        $user = $this->makeUser('GENERAL_USER', 'Plain');

        // Deactivated with no reason — "contact the Association", no appeal.
        $user->forceFill(['USR_STATUS' => 'DEACTIVATED'])->save();

        $this->postJson('/api/appeals/account', [
            'email' => $user->USR_EMAIL,
            'password' => 'password123',
            'reason' => 'Please restore',
        ])->assertStatus(403)
            ->assertJsonPath('message', 'This account is not appealable.');
    }
}
