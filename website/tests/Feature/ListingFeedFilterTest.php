<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\ContactLog;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The public feed's filter and sort params: GET /api/listings?category=&status=&sort=
 *
 * These run against MySQL rather than sqlite on purpose. The "popular" sort
 * leans on withCount, and the "date" sort on a raw NULLS-LAST ORDER BY that
 * only behaves correctly on the real engine.
 */
class ListingFeedFilterTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private CropCategory $leafy;

    private CropCategory $root;

    private Farm $farm;

    private Farmer $farmer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::create([
            'USR_ID' => 'USR001',
            'USR_NAME' => 'Feed Filter Buyer',
            'USR_EMAIL' => 'buyer@example.test',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '09171234567',
            'USR_ROLE' => 'GENERAL_USER',
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);

        // The chain "Become a Seller" creates: user -> buyer -> farmer -> farm.
        // Each FK is NOT NULL with no default, farm.FMR_ID points at farmer, and
        // every id column is char(6) — so the order and the lengths here are the
        // ones the schema demands, not choices.
        $buyerRow = Buyer::create([
            'BUY_ID' => 'BUY001',
            'USR_ID' => $this->buyer->USR_ID,
        ]);

        $this->farmer = Farmer::create([
            'FMR_ID' => 'FMR001',
            'BUY_ID' => $buyerRow->BUY_ID,
            'FMR_SELLER_MODE_ACTIVE' => 1,
        ]);

        $this->farm = Farm::create([
            'FRM_ID' => 'FRM001',
            'FRM_NAME' => 'Reyes Farm',
            'FRM_BARANGAY' => 'Rizal',
            'FRM_LATITUDE' => 14.676493,
            'FRM_LONGITUDE' => 121.04173,
            'FRM_STATUS' => 'APPROVED',
            'FRM_PIN_ACTIVE' => 1,
            'FRM_CREATED_AT' => now(),
            'FMR_ID' => $this->farmer->FMR_ID,
        ]);

        $this->leafy = CropCategory::create([
            'CAT_ID' => 'LEAFVG',
            'CAT_NAME' => 'Leafy Vegetables',
            'CAT_ICON' => 'spa',
        ]);

        $this->root = CropCategory::create([
            'CAT_ID' => 'ROOTCP',
            'CAT_NAME' => 'Root Crops',
            'CAT_ICON' => 'agriculture',
        ]);
    }

    private function makeListing(
        string $id,
        string $categoryId,
        string $status,
        string $createdAt,
        ?string $harvestDate = null
    ): Listing {
        return Listing::create([
            'LST_ID' => $id,
            'LST_CROP_ICON' => "Crop {$id}",
            'LST_STATUS' => $status,
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_HARVEST_DATE' => $harvestDate,
            'LST_EXPIRY_DATE' => now()->addDays(3),
            'LST_CREATED_AT' => $createdAt,
            'LST_UPDATED_AT' => $createdAt,
            'FMR_ID' => $this->farmer->FMR_ID,
            'FRM_ID' => $this->farm->FRM_ID,
            'CAT_ID' => $categoryId,
        ]);
    }

    private function logContacts(string $listingId, int $times): void
    {
        for ($i = 0; $i < $times; $i++) {
            ContactLog::create([
                'CTL_ID' => strtoupper(Str::random(6)),
                'USR_ID' => $this->buyer->USR_ID,
                'LST_ID' => $listingId,
                'CTL_METHOD' => 'CALL',
                'CTL_CREATED_AT' => now(),
            ]);
        }
    }

    private function idsFrom(array $payload): array
    {
        return array_column($payload['listings'], 'id');
    }

    // ------------------------------------------------ category

    public function test_a_category_param_narrows_the_feed_to_that_category()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'ROOTCP', 'AVAILABLE_NOW', '2026-01-02 09:00:00');

        $response = $this->getJson('/api/listings?category=ROOTCP');

        $response->assertOk();
        $this->assertSame(['LST002'], $this->idsFrom($response->json()));
    }

    public function test_an_absent_category_param_returns_both_categories()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'ROOTCP', 'AVAILABLE_NOW', '2026-01-02 09:00:00');

        $response = $this->getJson('/api/listings');

        $response->assertOk();
        $this->assertCount(2, $response->json('listings'));
    }

    // ------------------------------------------------ availability

    public function test_available_now_and_soon_to_harvest_filter_on_status()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'LEAFVG', 'SOON_TO_HARVEST', '2026-01-02 09:00:00');

        $availableNow = $this->getJson('/api/listings?status=AVAILABLE_NOW');
        $availableNow->assertOk();
        $this->assertSame(['LST001'], $this->idsFrom($availableNow->json()));

        $soon = $this->getJson('/api/listings?status=SOON_TO_HARVEST');
        $soon->assertOk();
        $this->assertSame(['LST002'], $this->idsFrom($soon->json()));
    }

    public function test_an_unknown_status_is_ignored_rather_than_returning_nothing()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');

        // NOT_AVAILABLE is a real enum value but is not a filter the app offers,
        // and a hand-typed value must not become an ORDER BY or a tautology.
        $response = $this->getJson('/api/listings?status=NOT_AVAILABLE');

        $response->assertOk();
        $this->assertCount(1, $response->json('listings'));
    }

    public function test_not_available_listings_are_never_in_the_feed()
    {
        $this->makeListing('LST001', 'LEAFVG', 'NOT_AVAILABLE', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-02 09:00:00');

        $response = $this->getJson('/api/listings');

        $response->assertOk();
        $this->assertSame(['LST002'], $this->idsFrom($response->json()));
    }

    // ------------------------------------------------ sorting

    public function test_latest_puts_the_newest_post_first()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-03 09:00:00');
        $this->makeListing('LST003', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-02 09:00:00');

        $response = $this->getJson('/api/listings?sort=latest');

        $response->assertOk();
        $this->assertSame(
            ['LST002', 'LST003', 'LST001'],
            $this->idsFrom($response->json())
        );
    }

    public function test_by_date_puts_the_soonest_harvest_first_and_nulls_last()
    {
        $this->makeListing('LST001', 'LEAFVG', 'SOON_TO_HARVEST', '2026-01-01 09:00:00', '2026-02-01');
        $this->makeListing('LST002', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-02 09:00:00', '2026-01-10');
        $this->makeListing('LST003', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-03 09:00:00', '2026-01-20');
        // No harvest date set: must sink to the bottom, not lead the feed.
        $this->makeListing('LST004', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-04 09:00:00', null);

        $response = $this->getJson('/api/listings?sort=date');

        $response->assertOk();
        $this->assertSame(
            ['LST002', 'LST003', 'LST001', 'LST004'],
            $this->idsFrom($response->json())
        );
    }

    public function test_popular_ranks_by_how_many_buyers_contacted_the_seller()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-02 09:00:00');
        $this->makeListing('LST003', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-03 09:00:00');

        $this->logContacts('LST001', 3);
        $this->logContacts('LST002', 1);

        $response = $this->getJson('/api/listings?sort=popular');

        $response->assertOk();
        // LST003 has no contacts at all, so it trails both.
        $this->assertSame(
            ['LST001', 'LST002', 'LST003'],
            $this->idsFrom($response->json())
        );
    }

    public function test_popular_breaks_a_tie_by_newest_first()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-02 09:00:00');

        $this->logContacts('LST001', 2);
        $this->logContacts('LST002', 2);

        $response = $this->getJson('/api/listings?sort=popular');

        $response->assertOk();
        // Equal contact counts must not reshuffle between refreshes.
        $this->assertSame(
            ['LST002', 'LST001'],
            $this->idsFrom($response->json())
        );
    }

    public function test_an_unknown_sort_falls_back_to_latest()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-02 09:00:00');

        $response = $this->getJson('/api/listings?sort=id%3B+DROP+TABLE+listing');

        $response->assertOk();
        $this->assertSame(
            ['LST002', 'LST001'],
            $this->idsFrom($response->json())
        );
    }

    // ------------------------------------------------ combinations

    public function test_a_category_and_a_sort_apply_together()
    {
        $this->makeListing('LST001', 'ROOTCP', 'AVAILABLE_NOW', '2026-01-01 09:00:00', '2026-01-05');
        $this->makeListing('LST002', 'ROOTCP', 'AVAILABLE_NOW', '2026-01-02 09:00:00', '2026-01-15');
        $this->makeListing('LST003', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-03 09:00:00', '2026-01-01');

        $response = $this->getJson('/api/listings?category=ROOTCP&sort=date');

        $response->assertOk();
        $this->assertSame(['LST001', 'LST002'], $this->idsFrom($response->json()));
    }

    public function test_search_and_filters_combine()
    {
        $this->makeListing('LST001', 'ROOTCP', 'AVAILABLE_NOW', '2026-01-01 09:00:00');
        $this->makeListing('LST002', 'ROOTCP', 'AVAILABLE_NOW', '2026-01-02 09:00:00');
        $this->makeListing('LST003', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-03 09:00:00');

        $response = $this->getJson('/api/listings?search=Crop+LST001&category=ROOTCP');

        $response->assertOk();
        $this->assertSame(['LST001'], $this->idsFrom($response->json()));
    }

    public function test_the_feed_shape_is_unchanged_when_nothing_is_filtered()
    {
        $this->makeListing('LST001', 'LEAFVG', 'AVAILABLE_NOW', '2026-01-01 09:00:00');

        $response = $this->getJson('/api/listings');

        $response->assertOk();
        $response->assertJsonStructure([
            'listings' => [[
                'id', 'crop_icon', 'status', 'availability', 'harvest_date',
                'expiry_date', 'description', 'image', 'created_at',
                'category', 'farm', 'photos',
            ]],
        ]);
    }
}
