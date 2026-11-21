<?php

namespace Tests\Feature;

use App\Services\CropSearchInsights;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class CropSearchInsightsTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'database.default' => 'insights_test',
            'database.connections.insights_test' => ['driver' => 'sqlite', 'database' => ':memory:'],
            'farmspot.insights_demo' => true,
            'cache.default' => 'array',
        ]);
        DB::statement('CREATE TABLE search_log (SRCH_CREATED_AT DATETIME, SRCH_KEYWORD TEXT, USR_ID TEXT)');
        DB::statement('CREATE TABLE listing (LST_STATUS TEXT, LST_AVAILABILITY TEXT, LST_EXPIRY_DATE DATETIME, LST_CROP_ICON TEXT, CAT_ID TEXT)');
        DB::statement('CREATE TABLE crop_category (CAT_ID TEXT, CAT_NAME TEXT)');
        DB::statement('CREATE TABLE trend (TRND_PERIOD_MONTH TEXT, TRND_TITLE TEXT, TRND_DATA TEXT)');
        $migration = require database_path('migrations/2026_11_21_000100_add_crop_search_insights_storage.php');
        $migration->up();
    }

    public function test_demo_labels_ties_and_undo(): void
    {
        $this->artisan('insights:demo')->assertSuccessful();
        $response = $this->getJson('/api/insights')->assertOk()
            ->assertJsonPath('search_interest.is_demo', true)
            ->assertJsonPath('search_interest.month_key', '2026-11')
            ->assertJsonPath('search_interest.forecast.0.month_key', '2026-12')
            ->assertJsonPath('search_interest.forecast.1.month_key', '2027-01')
            ->assertJsonPath('search_interest.forecast.2.month_key', '2027-02')
            ->assertJsonPath('search_interest.forecast.0.based_on', ['Dec 2025', 'Dec 2024']);
        $this->assertNotEmpty($response->json('search_interest.forecast.0.crops'));
        $this->assertSame('High', collect($response->json('search_interest.predictions'))->firstWhere('crop', 'tomato')['confidence']);
        $this->assertSame('Medium', collect($response->json('search_interest.predictions'))->firstWhere('crop', 'lettuce')['confidence']);
        $this->assertSame('Low', collect($response->json('search_interest.predictions'))->firstWhere('crop', 'ginger')['confidence']);
        $this->assertCount(4, collect($response->json('search_interest.trending'))->where('count', 12));
        $this->assertSame(105, DB::table('insight_demo_searches')->distinct()->count('searcher'));
        $this->assertSame(0, DB::table('search_log')->count());
        $service = app(CropSearchInsights::class);
        $this->assertEquals($response->json('search_interest'), $service->snapshot());
        $this->artisan('insights:demo', ['--undo' => true])->assertSuccessful();
        $this->assertSame(0, DB::table('insight_demo_listings')->count());
        $this->assertSame([], $service->snapshot()['predictions']);
    }

    public function test_production_refuses_demo_commands_and_mode(): void
    {
        $this->app->instance('env', 'production');
        $this->assertFalse(CropSearchInsights::demoEnabled());
        $this->artisan('insights:demo')->assertFailed();
        $this->artisan('insights:demo', ['--undo' => true])->assertFailed();
    }

    public function test_manila_year_boundary_leap_day_and_aliases(): void
    {
        config(['farmspot.insights_demo' => false, 'app.timezone' => 'UTC']);
        $this->travelTo(\Illuminate\Support\Carbon::parse('2024-02-29 16:05:00', 'UTC'));
        try {
            for ($user = 1; $user <= 8; $user++) {
                foreach ([
                    ['  Bok Choy ', '2024-02-29 15:45:00'],
                    ['pechay', '2024-02-29 15:50:00'],
                    ['tomato', '2023-12-31 16:00:00'],
                    ['<b>sample crop</b>', '2024-02-29 15:50:00'],
                ] as [$crop, $at]) {
                    DB::table('search_log')->insert([
                        'SRCH_CREATED_AT' => $at, 'SRCH_KEYWORD' => $crop, 'USR_ID' => $user,
                    ]);
                }
            }

            $snapshot = $this->getJson('/api/insights')->assertOk()
                ->assertJsonPath('search_interest.month_key', '2024-03')
                ->json('search_interest');
            $comparison = collect($snapshot['comparison']);
            $this->assertSame(8, $comparison->firstWhere('crop', 'bok choy')['searchers']);
            $this->assertSame(8, $comparison->firstWhere('crop', '<b>sample crop</b>')['searchers']);
            $this->assertNull($comparison->firstWhere('crop', 'tomato'));
            $this->assertSame([], $snapshot['predictions']);

            $this->travelTo(\Illuminate\Support\Carbon::parse('2023-12-31 16:05:00', 'UTC'));
            $this->getJson('/api/insights')->assertOk()->assertJsonPath('search_interest.month_key', '2024-01');
        } finally {
            $this->travelBack();
        }
    }
}
