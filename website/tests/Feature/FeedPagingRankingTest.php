<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\ContactLog;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\ListingReview;
use App\Models\SearchLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Feed paging and ranking: GET /api/listings?page=&per_page=&personalized=1
 *
 * Two things are being defended here, and they are different in kind:
 *
 *   1. An unpaged caller still gets exactly what it always got. The app's search
 *      screen and its as-you-type suggestions depend on the whole set, and
 *      suggestions fire on every keystroke.
 *   2. The ranking actually ranks. Popularity is rating-led, with contacts only
 *      a nudge, and unrated is not zero.
 *
 * Runs on MySQL because the ranked path uses withCount subqueries and a
 * nullable created_at ordering.
 */
class FeedPagingRankingTest extends TestCase
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
            'USR_NAME' => 'Feed Rank Buyer',
            'USR_EMAIL' => 'rank@example.test',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '09171234567',
            'USR_ROLE' => 'GENERAL_USER',
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);

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
        ?string $createdAt = null,
        int $daysAgo = 0
    ): Listing {
        $created = $createdAt ?? now()->subDays($daysAgo);

        return Listing::create([
            'LST_ID' => $id,
            'LST_CROP_ICON' => "Crop {$id}",
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_EXPIRY_DATE' => now()->addDays(3),
            'LST_CREATED_AT' => $created,
            'LST_UPDATED_AT' => $created,
            'FMR_ID' => $this->farmer->FMR_ID,
            'FRM_ID' => $this->farm->FRM_ID,
            'CAT_ID' => $categoryId,
        ]);
    }

    private function rate(Listing $listing, int $rating, int $times): void
    {
        for ($i = 0; $i < $times; $i++) {
            $reviewer = User::create([
                'USR_ID' => 'R' . strtoupper(Str::random(5)),
                'USR_NAME' => "Reviewer {$i} {$listing->LST_ID}",
                'USR_EMAIL' => "r{$i}_{$rating}_{$listing->LST_ID}@example.test",
                'USR_PASSWORD' => bcrypt('password123'),
                // The mobile number is unique, so it is derived from rating + listing + index
                // rather than just the index. A listing rated at 5 and again at 4
                // creates two reviewers at the same $i and would collide.
                'USR_MOBILE_NUMBER' => '0917' . substr(md5($listing->LST_ID . $rating . $i), 0, 7),
                'USR_ROLE' => 'GENERAL_USER',
                'USR_STATUS' => 'ACTIVE',
                'USR_CREATED_AT' => now(),
            ]);

            ListingReview::create([
                'LRV_ID' => strtoupper(Str::random(6)),
                'LST_ID' => $listing->LST_ID,
                'USR_ID' => $reviewer->USR_ID,
                'LRV_RATING' => $rating,
                'LRV_STATUS' => 'VISIBLE',
                'LRV_CREATED_AT' => now(),
                'LRV_UPDATED_AT' => now(),
            ]);
        }
    }

    private function logContacts(Listing $listing, int $times): void
    {
        for ($i = 0; $i < $times; $i++) {
            ContactLog::create([
                'CTL_ID' => strtoupper(Str::random(6)),
                'USR_ID' => $this->buyer->USR_ID,
                'LST_ID' => $listing->LST_ID,
                'CTL_METHOD' => 'CALL',
                'CTL_CREATED_AT' => now(),
            ]);
        }
    }

    private function logSearch(string $keyword, int $daysAgo = 0): void
    {
        SearchLog::create([
            'SRCH_ID' => strtoupper(Str::random(6)),
            'SRCH_KEYWORD' => $keyword,
            'SRCH_CREATED_AT' => now()->subDays($daysAgo),
            'USR_ID' => $this->buyer->USR_ID,
        ]);
    }

    private function idsFrom(array $payload): array
    {
        return array_column($payload['listings'], 'id');
    }

    public function test_an_unpaged_caller_still_receives_the_whole_feed_and_no_pagination()
    {
        // Twelve listings is more than a page, so a default-to-paged endpoint
        // would visibly truncate here.
        for ($i = 1; $i <= 12; $i++) {
            $this->makeListing(sprintf('LST%03d', $i), 'LEAFVG', daysAgo: $i);
        }

        $response = $this->getJson('/api/listings');

        $response->assertOk();
        $this->assertCount(12, $response->json('listings'));
        $response->assertJsonMissingPath('pagination');
    }

    public function test_paging_returns_a_slice_and_its_metadata()
    {
        for ($i = 1; $i <= 12; $i++) {
            $this->makeListing(sprintf('LST%03d', $i), 'LEAFVG', daysAgo: $i);
        }

        $response = $this->getJson('/api/listings?page=2&per_page=5');

        $response->assertOk();
        $this->assertCount(5, $response->json('listings'));
        $response->assertJsonPath('pagination.current_page', 2);
        $response->assertJsonPath('pagination.per_page', 5);
        // 12 candidates over 5 per page is 3 pages.
        $response->assertJsonPath('pagination.last_page', 3);
    }

    public function test_pages_do_not_overlap_or_repeat_a_listing()
    {
        for ($i = 1; $i <= 10; $i++) {
            $this->makeListing(sprintf('LST%03d', $i), 'LEAFVG', daysAgo: $i);
        }

        $first = $this->idsFrom($this->getJson('/api/listings?page=1&per_page=5')->json());
        $second = $this->idsFrom($this->getJson('/api/listings?page=2&per_page=5')->json());

        $this->assertCount(5, $first);
        $this->assertCount(5, $second);
        $this->assertEmpty(
            array_intersect($first, $second),
            'a listing on two pages would show as a duplicate card'
        );
    }

    public function test_a_per_page_beyond_the_ceiling_is_clamped_not_rejected()
    {
        for ($i = 1; $i <= 5; $i++) {
            $this->makeListing(sprintf('LST%03d', $i), 'LEAFVG', daysAgo: $i);
        }

        // Clamping rather than 422 on purpose: this route is public, and a
        // hand-typed per_page must not start failing.
        $response = $this->getJson('/api/listings?page=1&per_page=9999');

        $response->assertOk();
        $response->assertJsonPath('pagination.per_page', 30);
    }

    public function test_a_well_reviewed_crop_outranks_a_single_lucky_five_star()
    {
        // The whole reason the popularity term is a Bayesian average. A naive
        // average-times-count score would rank the single 5-star review first.
        $lucky = $this->makeListing('LST001', 'LEAFVG', daysAgo: 1);
        $loved = $this->makeListing('LST002', 'LEAFVG', daysAgo: 1);

        $this->rate($lucky, 5, 1);
        $this->rate($loved, 5, 30);
        $this->rate($loved, 4, 20);

        $ids = $this->idsFrom(
            $this->getJson('/api/listings?page=1&per_page=10&personalized=1')->json()
        );

        $luckyPos = array_search('LST001', $ids, true);
        $lovedPos = array_search('LST002', $ids, true);

        $this->assertLessThan(
            $luckyPos,
            $lovedPos,
            'fifty reviews at 4.6 must beat one review at 5.0'
        );
    }

    public function test_a_paged_explicit_sort_is_honoured_and_not_ranked()
    {
        // The buyer's chosen sort has to survive paging. Ranking anyway would
        // quietly answer a different question than the one that was asked: here
        // the older listing has the contacts and must lead, while the newer one
        // would win on freshness if this went through the ranked path.
        $fresh = $this->makeListing('LST101', 'LEAFVG', daysAgo: 0);
        $busy = $this->makeListing('LST102', 'LEAFVG', daysAgo: 30);

        $this->logContacts($busy, 25);

        $response = $this->getJson('/api/listings?sort=popular&page=1&per_page=10');

        $response->assertOk();
        $this->assertSame(
            ['LST102', 'LST101'],
            $this->idsFrom($response->json()),
            'twenty-five contacts lead a popular sort; freshness must not step in'
        );
        $response->assertJsonPath('pagination.total', 2);
    }

    public function test_pagination_metadata_describes_the_set_the_pages_come_from()
    {
        for ($i = 1; $i <= 12; $i++) {
            $this->makeListing(sprintf('LST%03d', $i), 'LEAFVG', daysAgo: $i);
        }

        $sorted = $this->getJson('/api/listings?page=2&per_page=5')->json();
        $ranked = $this->getJson('/api/listings?page=2&per_page=5&personalized=1')->json();

        // total and last_page have to be about the same set. A total of 2 beside
        // a last_page of 3 is what an app uses to decide it has reached the end,
        // and getting it wrong is either a dead "Load more" or a blank page.
        foreach (['sorted' => $sorted, 'ranked' => $ranked] as $case => $payload) {
            $this->assertSame(2, $payload['pagination']['current_page'], $case);
            $this->assertSame(5, $payload['pagination']['per_page'], $case);
            $this->assertSame(12, $payload['pagination']['total'], $case);
            $this->assertSame(3, $payload['pagination']['last_page'], $case);
            $this->assertCount(5, $payload['listings'], $case);
        }
    }

    public function test_an_unrated_listing_is_not_ranked_as_zero()
    {
        // Same posted day, so freshness cannot decide it and the rating has to.
        $rated = $this->makeListing('LST003', 'LEAFVG', daysAgo: 3);
        $unrated = $this->makeListing('LST004', 'LEAFVG', daysAgo: 3);

        $this->rate($rated, 4, 10);

        $response = $this->getJson('/api/listings?page=1&per_page=10&personalized=1');

        // Both listings come back; the rating is what separates them, and an
        // unreviewed one still carries a real payload rather than being hidden.
        $ids = $this->idsFrom($response->json());
        $this->assertContains('LST004', $ids);
        $this->assertNull(
            collect($response->json('listings'))->firstWhere('id', 'LST004')['rating_average'],
            'unrated is null, never 0.0 — no reviews is not bad ratings'
        );
        $this->assertLessThan(
            array_search('LST004', $ids, true),
            array_search('LST003', $ids, true),
            'ten real reviews must beat no reviews'
        );
    }

    public function test_contacts_break_a_tie()
    {
        // Identical ratings on all three. The one people actually contacted has
        // to come first, or "popular" means nothing when ratings are equal.
        $busy = $this->makeListing('LST005', 'LEAFVG', daysAgo: 3);
        $quiet = $this->makeListing('LST006', 'LEAFVG', daysAgo: 3);
        $alsoQuiet = $this->makeListing('LST007', 'LEAFVG', daysAgo: 3);

        $this->rate($busy, 5, 8);
        $this->rate($quiet, 5, 8);
        $this->rate($alsoQuiet, 5, 8);

        $this->logContacts($busy, 20);

        $ids = $this->idsFrom(
            $this->getJson('/api/listings?page=1&per_page=10&personalized=1')->json()
        );

        $this->assertLessThan(
            array_search('LST006', $ids, true),
            array_search('LST005', $ids, true),
            'twenty contacts must settle a dead heat'
        );
        $this->assertLessThan(
            array_search('LST007', $ids, true),
            array_search('LST005', $ids, true)
        );
    }

    public function test_contact_volume_cannot_outrank_a_properly_reviewed_crop()
    {
        // This is the ordering requirement stated as a test: rating first,
        // contacts second. Forty contacts on an unreviewed listing is not enough.
        $busy = $this->makeListing('LST008', 'LEAFVG', daysAgo: 3);
        $loved = $this->makeListing('LST009', 'LEAFVG', daysAgo: 3);

        $this->logContacts($busy, 40);
        $this->rate($loved, 5, 12);

        $ids = $this->idsFrom(
            $this->getJson('/api/listings?page=1&per_page=10&personalized=1')->json()
        );

        $this->assertLessThan(
            array_search('LST008', $ids, true),
            array_search('LST009', $ids, true),
            'contacts are a nudge; they must not become the ranking'
        );
    }

    public function test_recent_searches_lift_that_category_without_hiding_the_others()
    {
        $leafyOne = $this->makeListing('LST014', 'LEAFVG', daysAgo: 2);
        $leafyTwo = $this->makeListing('LST015', 'LEAFVG', daysAgo: 2);
        $rootOne = $this->makeListing('LST016', 'ROOTCP', daysAgo: 2);

        $this->logSearch('leafy');

        $response = $this->actingAs($this->buyer, 'sanctum')
            ->getJson('/api/listings?page=1&per_page=10&personalized=1');

        $response->assertOk();
        $ids = $this->idsFrom($response->json());

        // Every listing is still on the page. Affinity tilts the order, it does
        // not filter the feed down to one category.
        $this->assertContains('LST014', $ids);
        $this->assertContains('LST015', $ids);
        $this->assertContains('LST016', $ids);

        // Both leafy listings come before the unsearched category.
        $this->assertLessThan(array_search('LST016', $ids, true), array_search('LST014', $ids, true));
        $this->assertLessThan(array_search('LST016', $ids, true), array_search('LST015', $ids, true));
    }

    public function test_a_user_with_no_search_history_gets_the_fair_mix()
    {
        // New listings and low-contact ones must surface with no history at all,
        // which is the whole point of the discovery reserve.
        for ($i = 1; $i <= 4; $i++) {
            $this->makeListing(sprintf('LSTO%d', $i), 'LEAFVG', daysAgo: 40);
        }
        $this->makeListing('LST010', 'ROOTCP', daysAgo: 0);
        $this->makeListing('LST011', 'ROOTCP', daysAgo: 0);

        $ids = $this->idsFrom(
            $this->getJson('/api/listings?page=1&per_page=10&personalized=1')->json()
        );

        $this->assertContains('LST010', $ids);
        $this->assertContains('LST011', $ids);
    }

    public function test_the_discovery_reserve_appears_on_the_first_page()
    {
        // Four heavily contacted listings win on score alone, and they are posted on
        // the same day as the quiet ones so freshness cannot explain the quiet
        // ones' absence. The reserve is therefore the only thing that can put
        // them on page one.
        $quiet = [];
        for ($i = 1; $i <= 2; $i++) {
            $listing = $this->makeListing(sprintf('LSTQ%d', $i), 'LEAFVG', daysAgo: 1);
            $quiet[] = $listing->LST_ID;
        }

        for ($i = 1; $i <= 4; $i++) {
            $listing = $this->makeListing(sprintf('LSTY%d', $i), 'LEAFVG', daysAgo: 1);
            $this->logContacts($listing, 30);
        }

        $ids = $this->idsFrom(
            $this->getJson('/api/listings?page=1&per_page=4&personalized=1')->json()
        );

        foreach ($quiet as $id) {
            $this->assertContains($id, $ids, 'an under-exposed listing must reach page one');
        }
    }

    public function test_a_guest_gets_the_ranked_feed_without_personalisation()
    {
        // /listings is a public route, so an absent token has to work. The
        // ranking runs; only the per-user affinity term is missing.
        for ($i = 1; $i <= 3; $i++) {
            $this->makeListing(sprintf('LST%03d', $i), 'LEAFVG', daysAgo: $i);
        }

        $response = $this->getJson('/api/listings?page=1&per_page=10&personalized=1');

        $response->assertOk();
        $this->assertCount(3, $response->json('listings'));
    }

    public function test_search_still_works_alongside_paging()
    {
        $this->makeListing('LST012', 'LEAFVG', daysAgo: 1);
        $this->makeListing('LST013', 'ROOTCP', daysAgo: 1);

        $response = $this->getJson('/api/listings?search=Crop+LST012&page=1&per_page=10&personalized=1');

        $response->assertOk();
        $this->assertSame(['LST012'], $this->idsFrom($response->json()));
    }
}