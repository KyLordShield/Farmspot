<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\ListingReview;
use App\Models\Report;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The seller's own listing list: GET /api/my-listings with ?page, ?per_page,
 * ?farm_id, ?status and ?include_removed.
 *
 * The whole point of this endpoint is that it is called by ONE screen with a
 * bearer token, so everything here is about not surprising anyone else:
 *
 *  1. No paging parameters means no paging. The response is the previous one —
 *     every row, and no `pagination` key at all. An unpaged list is not a
 *     one-page list, and defaulting to pages would silently truncate every
 *     existing caller.
 *  2. per_page is clamped, never rejected. A client asking for 500 rows gets
 *     30 and a client sending nonsense gets the default, because this screen is
 *     reachable over a phone network and an error page is worse than a page.
 *  3. A seller's list never contains another seller's listing, whatever the
 *     query string says.
 *  4. The four status filters partition the scope, so the chip counts and the
 *     rows below them describe the same sets.
 *  5. `summary` is computed before the filter and over every review row, so a
 *     farm with 90 five-star reviews on one crop and 2 four-star reviews on
 *     another does not report the average of its averages.
 *  6. An open report sets a boolean and nothing else. No reporter, no reason, no
 *     details: the seller learns that the Association is looking, and the
 *     moderator keeps the accusation.
 *
 * The schema comes from a committed SQL dump plus migrations, so these run
 * against MySQL (see phpunit.mysql.xml).
 */
class MyFarmListingPageTest extends TestCase
{
    use RefreshDatabase;

    /** Every id in this schema is 6 characters, so these have to be too. */
    private function id(string $prefix): string
    {
        $table = [
            'USR' => 'user',
            'BUY' => 'buyer',
            'FMR' => 'farmer',
            'FRM' => 'farm',
            'LST' => 'listing',
            'CAT' => 'crop_category',
            'LRV' => 'listing_review',
        ][$prefix];

        $column = "{$prefix}_ID";

        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }

    private function makeUser(string $name, string $email): User
    {
        return User::create([
            'USR_ID' => $this->id('USR'),
            'USR_NAME' => $name,
            'USR_EMAIL' => $email,
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0917'.str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_IS_SELLER' => 1,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
    }

    /**
     * A seller with one approved farm, the shape "Become a Seller" produces.
     */
    private function makeSeller(string $name = 'Reyes', string $email = 'reyes@test.local'): array
    {
        $user = $this->makeUser($name, $email);
        $buyer = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $user->USR_ID]);
        $farmer = Farmer::create([
            'FMR_ID' => $this->id('FMR'),
            'BUY_ID' => $buyer->BUY_ID,
            'FMR_SELLER_MODE_ACTIVE' => 1,
        ]);
        $farm = Farm::create([
            'FRM_ID' => $this->id('FRM'),
            'FRM_NAME' => "{$name} Farm",
            'FRM_BARANGAY' => 'Sudlon II',
            'FRM_LATITUDE' => 10.30,
            'FRM_LONGITUDE' => 123.89,
            'FRM_STATUS' => 'APPROVED',
            'FRM_PIN_ACTIVE' => 1,
            'FRM_CREATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
        ]);

        return compact('user', 'buyer', 'farmer', 'farm');
    }

    private function categoryId(): string
    {
        return CropCategory::first()?->CAT_ID
            ?? CropCategory::create(['CAT_ID' => $this->id('CAT'), 'CAT_NAME' => 'Vegetables'])->CAT_ID;
    }

    private function makeListing(
        array $seller,
        string $status = 'AVAILABLE_NOW',
        string $availability = 'ACTIVE',
        ?string $farmId = null,
        ?\DateTimeInterface $expiry = null,
        ?\DateTimeInterface $createdAt = null,
    ): Listing {
        return Listing::create([
            'LST_ID' => $this->id('LST'),
            'LST_CROP_ICON' => 'Carrot',
            'LST_STATUS' => $status,
            'LST_AVAILABILITY' => $availability,
            'LST_EXPIRY_DATE' => $expiry ?? now()->addDays(3),
            'LST_CREATED_AT' => $createdAt ?? now(),
            'LST_UPDATED_AT' => $createdAt ?? now(),
            'FMR_ID' => $seller['farmer']->FMR_ID,
            'FRM_ID' => $farmId ?? $seller['farm']->FRM_ID,
            'CAT_ID' => $this->categoryId(),
        ]);
    }

    private function myListings(User $as, string $query = ''): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($as, 'sanctum')
            ->getJson('/api/my-listings'.$query);
    }

    private function seedReview(Listing $listing, int $rating, string $status = ListingReview::STATUS_VISIBLE): ListingReview
    {
        $buyer = $this->makeUser('Reviewer '.$rating, 'r'.$rating.random_int(100, 999).'@test.local');
        $buyerRow = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $buyer->USR_ID]);

        return ListingReview::create([
            'LRV_ID' => $this->id('LRV'),
            'LST_ID' => $listing->LST_ID,
            'USR_ID' => $buyer->USR_ID,
            'LRV_RATING' => $rating,
            'LRV_COMMENT' => 'Private words from a buyer',
            'LRV_STATUS' => $status,
            'LRV_CREATED_AT' => now(),
            'LRV_UPDATED_AT' => now(),
        ]);
    }

    private function seedReport(Listing $listing, string $status): Report
    {
        $reporter = $this->makeUser('Reporter', 'rep'.random_int(100, 999).'@test.local');

        return Report::create([
            'RPT_ID' => Report::newId(),
            'RPT_REASON' => 'Misleading or false information',
            'RPT_REASON_CODE' => 'MISLEADING_INFO',
            'RPT_DETAILS' => 'The seller claims organic but uses chemicals.',
            'USR_ID' => $reporter->USR_ID,
            'LST_ID' => $listing->LST_ID,
            'RPT_TARGET_TYPE' => Report::TARGET_LISTING,
            'RPT_TARGET_ID' => $listing->LST_ID,
            'RPT_STATUS' => $status,
            'RPT_CREATED_AT' => now(),
            'RPT_UPDATED_AT' => now(),
        ]);
    }

    // ------------------------------------------------------- old behaviour kept

    public function test_without_page_parameters_the_response_is_still_the_whole_list(): void
    {
        $seller = $this->makeSeller();
        for ($i = 0; $i < 25; $i++) {
            $this->makeListing($seller);
        }

        $response = $this->myListings($seller['user']);

        $response->assertOk()
            // No paging was asked for, so no paging is reported: a caller cannot
            // tell "there is no next page" from "this response is not paged".
            ->assertJsonMissingPath('pagination')
            ->assertJsonCount(25, 'listings');
    }

    public function test_removed_listings_are_still_excluded_unless_asked_for(): void
    {
        $seller = $this->makeSeller();
        $this->makeListing($seller);
        $this->makeListing($seller, availability: Listing::AVAILABILITY_REMOVED);

        $this->myListings($seller['user'])
            ->assertOk()
            ->assertJsonCount(1, 'listings');

        // The seller has to be able to SEE that a moderator took a crop down,
        // even though they cannot do anything about it.
        $this->myListings($seller['user'], '?page=1&include_removed=1')
            ->assertOk()
            ->assertJsonCount(2, 'listings')
            ->assertJsonPath('pagination.per_page', 10);
    }

    public function test_only_the_callers_own_listings_are_returned(): void
    {
        $mine = $this->makeSeller('Mine', 'mine@test.local');
        $theirs = $this->makeSeller('Theirs', 'theirs@test.local');

        $this->makeListing($mine);
        $this->makeListing($mine);
        $this->makeListing($theirs);

        $response = $this->myListings($mine['user'], '?page=1&per_page=30');

        $response->assertOk()
            ->assertJsonCount(2, 'listings')
            ->assertJsonPath('summary.total_listings', 2);
    }

    // ------------------------------------------------------------- page params

    public function test_paging_defaults_to_ten_per_page(): void
    {
        $seller = $this->makeSeller();
        for ($i = 0; $i < 12; $i++) {
            $this->makeListing($seller);
        }

        $this->myListings($seller['user'], '?page=1')
            ->assertOk()
            ->assertJsonCount(10, 'listings')
            ->assertJsonPath('pagination.current_page', 1)
            ->assertJsonPath('pagination.last_page', 2)
            ->assertJsonPath('pagination.total', 12)
            ->assertJsonPath('pagination.per_page', 10);
    }

    public function test_per_page_above_the_maximum_is_clamped_to_thirty(): void
    {
        $seller = $this->makeSeller();

        $this->myListings($seller['user'], '?page=1&per_page=500')
            ->assertOk()
            ->assertJsonPath('pagination.per_page', 30);
    }

    public function test_unusable_per_page_values_fall_back_instead_of_erroring(): void
    {
        $seller = $this->makeSeller();

        // Not numbers: the default, not a 422. This screen is on a phone.
        $this->myListings($seller['user'], '?page=1&per_page=lots')
            ->assertOk()
            ->assertJsonPath('pagination.per_page', 10);

        // Zero and negatives clamp up to one rather than returning nothing.
        $this->myListings($seller['user'], '?page=1&per_page=0')
            ->assertOk()
            ->assertJsonPath('pagination.per_page', 1);

        $this->myListings($seller['user'], '?page=1&per_page=-5')
            ->assertOk()
            ->assertJsonPath('pagination.per_page', 1);
    }

    public function test_pages_do_not_overlap_or_skip_rows(): void
    {
        $seller = $this->makeSeller();
        $created = [];
        for ($i = 0; $i < 25; $i++) {
            $created[] = $this->makeListing(
                $seller,
                createdAt: now()->subDays(30 - $i)
            )->LST_ID;
        }

        $first = $this->myListings($seller['user'], '?page=1&per_page=10')->json('listings');
        $second = $this->myListings($seller['user'], '?page=2&per_page=10')->json('listings');
        $third = $this->myListings($seller['user'], '?page=3&per_page=10')->json('listings');

        $ids = array_merge(
            array_column($first, 'id'),
            array_column($second, 'id'),
            array_column($third, 'id'),
        );

        // Newest first, and every row exactly once across the three pages. A
        // tie on LST_CREATED_AT without a tiebreaker is how a row gets served
        // twice, so this is asserted rather than assumed.
        $this->assertCount(25, $ids);
        $this->assertSame($ids, array_values(array_unique($ids)));
        $this->assertSame($created, array_reverse($ids));
    }

    public function test_a_page_beyond_the_end_is_empty_rather_than_an_error(): void
    {
        $seller = $this->makeSeller();
        $this->makeListing($seller);

        $this->myListings($seller['user'], '?page=9&per_page=10')
            ->assertOk()
            ->assertJsonCount(0, 'listings')
            // last_page stays at 1 so the app can never ask for page 2 forever.
            ->assertJsonPath('pagination.last_page', 1);
    }

    public function test_farm_id_scopes_the_list_and_the_summary_to_one_farm(): void
    {
        $seller = $this->makeSeller();
        $second = Farm::create([
            'FRM_ID' => $this->id('FRM'),
            'FRM_NAME' => 'Second Farm',
            'FRM_BARANGAY' => 'Basak',
            'FRM_LATITUDE' => 10.31,
            'FRM_LONGITUDE' => 123.90,
            'FRM_STATUS' => 'APPROVED',
            'FRM_PIN_ACTIVE' => 1,
            'FRM_CREATED_AT' => now(),
            'FMR_ID' => $seller['farmer']->FMR_ID,
        ]);

        $this->makeListing($seller);
        $this->makeListing($seller);
        $this->makeListing($seller, farmId: $second->FRM_ID);

        $query = '?page=1&per_page=30&farm_id='.$second->FRM_ID;

        $this->myListings($seller['user'], $query)
            ->assertOk()
            ->assertJsonCount(1, 'listings')
            ->assertJsonPath('summary.total_listings', 1);

        // Without the parameter, both farms: the multi-farm screen used to get
        // everything and pick one farm out of it client-side.
        $this->myListings($seller['user'], '?page=1&per_page=30')
            ->assertOk()
            ->assertJsonCount(3, 'listings')
            ->assertJsonPath('summary.total_listings', 3);
    }

    // ------------------------------------------------------------ status filter

    public function test_the_status_filter_selects_each_bucket(): void
    {
        $seller = $this->makeSeller();

        $active = $this->makeListing($seller);
        $soon = $this->makeListing($seller, 'SOON_TO_HARVEST');
        $expired = $this->makeListing($seller, 'NOT_AVAILABLE', 'ACTIVE', null, now()->subDay());
        $removed = $this->makeListing($seller, 'AVAILABLE_NOW', Listing::AVAILABILITY_REMOVED);
        $adminHidden = $this->makeListing($seller, 'AVAILABLE_NOW', 'NOT_AVAILABLE');
        $reported = $this->makeListing($seller);
        $this->seedReport($reported, 'New');

        $ids = fn (array $rows) => collect($rows)
            ->map(fn ($row) => is_array($row) ? $row['id'] : $row->LST_ID)
            ->sort()
            ->values()
            ->all();

        // All: everything except the admin-removed one, which is opt-in.
        $this->myListings($seller['user'], '?page=1&per_page=30')
            ->assertOk()
            ->assertJsonCount(5, 'listings');

        $this->assertSame(
            $ids([$active, $soon]),
            $ids($this->myListings($seller['user'], '?page=1&per_page=30&status=active')->json('listings')),
            'Active is everything that is neither expired, hidden nor under review.'
        );

        $this->assertSame(
            [$expired->LST_ID],
            $ids($this->myListings($seller['user'], '?page=1&per_page=30&status=expired')->json('listings')),
        );

        $this->assertSame(
            $ids([$removed, $adminHidden]),
            $ids($this->myListings($seller['user'], '?page=1&per_page=30&status=hidden&include_removed=1')->json('listings')),
        );

        $this->assertSame(
            [$reported->LST_ID],
            $ids($this->myListings($seller['user'], '?page=1&per_page=30&status=under_review')->json('listings')),
        );
    }

    public function test_an_unknown_status_filter_is_ignored_rather_than_rejected(): void
    {
        $seller = $this->makeSeller();
        $this->makeListing($seller);

        $this->myListings($seller['user'], '?page=1&per_page=30&status=nonsense')
            ->assertOk()
            ->assertJsonCount(1, 'listings');
    }

    public function test_the_filter_counts_partition_the_scope_and_ignore_the_active_filter(): void
    {
        $seller = $this->makeSeller();
        $this->makeListing($seller);
        $this->makeListing($seller);
        $expired = $this->makeListing($seller, 'NOT_AVAILABLE', 'ACTIVE', null, now()->subDay());
        $reported = $this->makeListing($seller);
        $this->seedReport($reported, 'Reviewing');

        // Filtering to "active" must not change what the chips say: a chip
        // reading "Expired 1" above a list of active crops is a filter chip
        // lying about the farm.
        // Four listings in total: two active, one expired, one under review. Filtering
        // the list must not change any of those numbers.
        $response = $this->myListings($seller['user'], '?page=1&per_page=30&status=active');

        $response->assertOk()
            ->assertJsonCount(2, 'listings')
            ->assertJsonPath('summary.total_listings', 4)
            ->assertJsonPath('summary.active_count', 2)
            ->assertJsonPath('summary.expired_count', 1)
            ->assertJsonPath('summary.under_review_count', 1)
            ->assertJsonPath('summary.hidden_count', 0);
    }

    // ------------------------------------------------------------------ ratings

    public function test_each_listing_carries_its_own_rating_summary(): void
    {
        $seller = $this->makeSeller();
        $reviewed = $this->makeListing($seller);
        $this->makeListing($seller);

        $this->seedReview($reviewed, 5);
        $this->seedReview($reviewed, 4);
        // A hidden review is out of the number, exactly as it is for a buyer.
        $this->seedReview($reviewed, 1, ListingReview::STATUS_HIDDEN);

        $rows = collect($this->myListings($seller['user'], '?page=1&per_page=30')->json('listings'))
            ->keyBy('id');

        $this->assertSame(2, $rows[$reviewed->LST_ID]['rating_count']);
        $this->assertSame(4.5, (float) $rows[$reviewed->LST_ID]['rating_average']);

        // Unreviewed is null, never 0.0: "no reviews" and "scored zero" are
        // different states and the app renders them differently.
        $unreviewed = $rows->firstWhere('rating_count', 0);
        $this->assertNull($unreviewed['rating_average']);
    }

    public function test_the_farm_summary_average_weights_every_review_not_every_listing(): void
    {
        $seller = $this->makeSeller();

        // One crop with four 5s, one with a single 1. Averaging the two
        // per-listing averages gives 3.0; the honest answer is 21/5 = 4.2.
        $big = $this->makeListing($seller);
        for ($i = 0; $i < 4; $i++) {
            $this->seedReview($big, 5);
        }
        $small = $this->makeListing($seller);
        $this->seedReview($small, 1);

        $response = $this->myListings($seller['user'], '?page=1&per_page=30');

        $response->assertOk()
            ->assertJsonPath('summary.review_count', 5)
            ->assertJsonPath('summary.total_listings', 2);

        $this->assertSame(4.2, (float) $response->json('summary.rating_average'));
    }

    public function test_the_summary_rating_is_null_when_nothing_has_been_reviewed(): void
    {
        $seller = $this->makeSeller();
        $this->makeListing($seller);

        $this->myListings($seller['user'], '?page=1&per_page=30')
            ->assertOk()
            ->assertJsonPath('summary.review_count', 0)
            ->assertJsonPath('summary.rating_average', null);
    }

    public function test_the_summary_average_ignores_another_farms_reviews(): void
    {
        $mine = $this->makeSeller('Mine', 'mine@test.local');
        $theirs = $this->makeSeller('Theirs', 'theirs@test.local');

        $myListing = $this->makeListing($mine);
        $this->seedReview($myListing, 2);
        $this->seedReview($this->makeListing($theirs), 5);

        // Asserted as 2 rather than 2.0: json_encode() drops the ".0" from a
        // whole number, so a 2.0 average arrives as the int 2.
        $this->myListings($mine['user'], '?page=1&per_page=30')
            ->assertOk()
            ->assertJsonPath('summary.review_count', 1)
            ->assertJsonPath('summary.rating_average', 2);
    }

    // ------------------------------------------------------------ report chips

    public function test_an_open_report_flags_the_listing_and_a_closed_one_does_not(): void
    {
        $seller = $this->makeSeller();

        $new = $this->makeListing($seller);
        $reviewing = $this->makeListing($seller);
        $resolved = $this->makeListing($seller);
        $dismissed = $this->makeListing($seller);
        $clean = $this->makeListing($seller);

        $this->seedReport($new, 'New');
        $this->seedReport($reviewing, 'Reviewing');
        $this->seedReport($resolved, 'Resolved');
        $this->seedReport($dismissed, 'Dismissed');

        $rows = collect($this->myListings($seller['user'], '?page=1&per_page=30')->json('listings'))
            ->keyBy('id');

        $this->assertTrue($rows[$new->LST_ID]['has_open_report']);
        $this->assertTrue($rows[$reviewing->LST_ID]['has_open_report']);
        $this->assertFalse($rows[$resolved->LST_ID]['has_open_report']);
        $this->assertFalse($rows[$dismissed->LST_ID]['has_open_report']);
        $this->assertFalse($rows[$clean->LST_ID]['has_open_report']);

        $response = $this->myListings($seller['user'], '?page=1&per_page=30&status=under_review');

        $response->assertOk()->assertJsonCount(2, 'listings');
    }

    public function test_the_response_never_carries_who_reported_or_why(): void
    {
        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller);
        $report = $this->seedReport($listing, 'New');

        $body = $this->myListings($seller['user'], '?page=1&per_page=30')->getContent();

        $response = $this->myListings($seller['user'], '?page=1&per_page=30');

        // The seller learns that the Association is looking at the listing. The
        // accusation, the reporter and their words stay on the admin side.
        $this->assertStringNotContainsString($report->RPT_ID, $body);
        $this->assertStringNotContainsString($report->USR_ID, $body);
        $this->assertStringNotContainsString('MISLEADING_INFO', $body);
        $this->assertStringNotContainsString('uses chemicals', $body);
        $response->assertJsonMissingPath('listings.0.reports')
            ->assertJsonMissingPath('listings.0.report_status')
            ->assertJsonMissingPath('listings.0.reporter')
            ->assertJsonMissingPath('listings.0.reason')
            ->assertJsonMissingPath('listings.0.details')
            ->assertJsonMissingPath('listings.0.report_id');
    }

    // --------------------------------------------------------------- authority

    public function test_a_seller_without_a_farmer_account_is_refused_as_before(): void
    {
        $user = $this->makeUser('No Farm', 'nofarm@test.local');
        Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $user->USR_ID]);

        $this->myListings($user, '?page=1')
            ->assertStatus(403)
            ->assertJsonPath('message', 'No farmer account found.');
    }
}