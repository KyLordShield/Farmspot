<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\Report;
use App\Models\SearchLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

class AnalyticsTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(Carbon::parse('2026-10-31 12:00:00'));
        Http::fake();
        $this->admin = $this->user('ADMIN');
    }

    private function user(string $role = 'GENERAL_USER', ?string $created = null): User
    {
        $id = strtoupper(Str::random(6));

        return User::create(['USR_ID' => $id, 'USR_NAME' => 'Analytics '.$id, 'USR_EMAIL' => $id.'@analytics.test', 'USR_PASSWORD' => bcrypt('password123'), 'USR_MOBILE_NUMBER' => '09'.$id, 'USR_ROLE' => $role, 'USR_STATUS' => 'ACTIVE', 'USR_CREATED_AT' => $created ?? '2026-09-01 12:00:00']);
    }

    private function listing(array $changes = [], ?Farmer $farmer = null): Listing
    {
        if ($farmer === null) {
            $user = $this->user();
            $user->forceFill(['USR_IS_SELLER' => 1])->save();
            $buyer = Buyer::create(['BUY_ID' => strtoupper(Str::random(6)), 'USR_ID' => $user->USR_ID]);
            $farmer = Farmer::create(['FMR_ID' => strtoupper(Str::random(6)), 'BUY_ID' => $buyer->BUY_ID, 'FMR_SELLER_MODE_ACTIVE' => 1]);
        }
        $farm = Farm::create(['FRM_ID' => strtoupper(Str::random(6)), 'FMR_ID' => $farmer->FMR_ID, 'FRM_NAME' => 'Analytics Farm', 'FRM_BARANGAY' => 'Sudlon', 'FRM_LATITUDE' => 10.3, 'FRM_LONGITUDE' => 123.9, 'FRM_STATUS' => 'APPROVED', 'FRM_CREATED_AT' => now()]);

        return Listing::create(array_merge(['LST_ID' => strtoupper(Str::random(6)), 'FRM_ID' => $farm->FRM_ID, 'FMR_ID' => $farmer->FMR_ID, 'CAT_ID' => CropCategory::firstOrFail()->CAT_ID, 'LST_CROP_ICON' => 'Cabbage', 'LST_STATUS' => 'AVAILABLE_NOW', 'LST_AVAILABILITY' => 'ACTIVE', 'LST_CREATED_AT' => now(), 'LST_UPDATED_AT' => now(), 'LST_EXPIRY_DATE' => now()->addDays(3)], $changes));
    }

    private function search(string $term, string $when): void
    {
        SearchLog::create(['SRCH_ID' => strtoupper(Str::random(6)), 'USR_ID' => $this->admin->USR_ID, 'SRCH_KEYWORD' => $term, 'SRCH_CREATED_AT' => $when]);
    }

    public function test_access_is_admin_only_and_empty_data_renders_honestly(): void
    {
        $this->get('/analytics')->assertRedirect('/login');
        $this->actingAs($this->user())->get('/analytics')->assertForbidden();
        $response = $this->actingAs($this->admin)->get('/analytics')->assertOk();
        $response->assertSee('No searches recorded this week yet.')->assertDontSee('Expected peak months');
        $response->assertViewHas('topSearches', fn ($rows) => $rows->isEmpty());
        $response->assertViewHas('monthlyTrends', fn ($rows) => count($rows) === 12 && array_sum(array_column($rows, 'total')) === 0);
        $response->assertViewHas('growthValues', [0, 0, 0, 0, 0]);
    }

    public function test_searches_use_real_logs_normalize_terms_and_respect_dates(): void
    {
        $this->search(' Pechay ', '2026-10-31 08:00:00');
        $this->search('pechay', '2026-10-31 09:00:00');
        $this->search('PECHAY', '2026-10-26 00:00:00');
        $this->search('old', '2026-10-25 23:59:59');
        $this->search('future', '2026-10-31 13:00:00');
        $this->search(' ', '2026-10-31 09:00:00');
        $this->search('</script><script>alert(1)</script>', '2026-10-30 09:00:00');
        $response = $this->actingAs($this->admin)->get('/analytics')->assertOk();
        $response->assertViewHas('searchesToday', 2);
        $rows = $response->viewData('topSearches');
        $this->assertCount(2, $rows);
        $this->assertSame('pechay', $rows[0]->keyword);
        $this->assertEquals(3, $rows[0]->total);
        $response->assertDontSee('</script><script>alert(1)</script>', false);
    }

    public function test_growth_includes_the_fifth_group_and_excludes_other_months_and_future(): void
    {
        foreach ([1, 7, 8, 14, 15, 21, 22, 28, 29, 31] as $day) {
            $this->user(created: sprintf('2026-10-%02d 08:00:00', $day));
        }
        $this->user(created: '2026-09-30 23:59:59');
        $this->user(created: '2026-10-31 13:00:00');
        $response = $this->actingAs($this->admin)->get('/analytics')->assertOk();
        $response->assertViewHas('growthValues', [2, 2, 2, 2, 2]);
        $response->assertViewHas('growthLabels', ['Oct 1–7', 'Oct 8–14', 'Oct 15–21', 'Oct 22–28', 'Oct 29–31']);
    }

    public function test_monthly_activity_and_summary_use_the_correct_records(): void
    {
        $first = $this->listing(['LST_EXPIRY_DATE' => now()->subDay()]);
        $farmer = Farmer::findOrFail($first->FMR_ID);
        $second = $this->listing(['LST_STATUS' => 'SOON_TO_HARVEST'], $farmer);
        $this->listing(['LST_AVAILABILITY' => 'NOT_AVAILABLE', 'LST_CROP_ICON' => 'Carrot'], $farmer);
        $this->listing(['LST_STATUS' => 'NOT_AVAILABLE', 'LST_CREATED_AT' => '2026-09-15 10:00:00', 'LST_CROP_ICON' => 'Potato'], $farmer);
        foreach (['New', 'Reviewing', 'Resolved', 'Dismissed'] as $status) {
            Report::create(['RPT_ID' => strtoupper(Str::random(6)), 'USR_ID' => $this->admin->USR_ID, 'LST_ID' => $first->LST_ID, 'RPT_TARGET_TYPE' => 'LISTING', 'RPT_TARGET_ID' => $first->LST_ID, 'RPT_REASON' => 'Test', 'RPT_STATUS' => $status, 'RPT_CREATED_AT' => now()]);
        }
        $response = $this->actingAs($this->admin)->get('/analytics')->assertOk();
        $response->assertViewHas('totalUsers', 2)->assertViewHas('totalBuyers', 1)->assertViewHas('totalFarmers', 1)->assertViewHas('totalListings', 2)->assertViewHas('totalReports', 2);
        $months = collect($response->viewData('monthlyTrends'))->keyBy('month');
        $this->assertSame(['month' => 'Oct 2026', 'crop' => 'Cabbage', 'top_count' => 2, 'total' => 3], $months['Oct 2026']);
        $this->assertSame('Potato', $months['Sep 2026']['crop']);
        $this->assertSame(0, $months['Nov 2025']['total']);
        Farm::where('FMR_ID', $farmer->FMR_ID)->update(['FRM_STATUS' => 'PENDING_REVIEW']);
        $this->get('/analytics')->assertOk()->assertViewHas('totalFarmers', 0);
    }
}
