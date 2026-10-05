<?php

namespace Tests\Feature;

use App\Models\Listing;
use App\Models\ListingReview;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The optional query parameters on GET /api/listings/{id}/reviews.
 *
 * Separate from ListingReviewTest because these are additive-narrowing tests:
 * the assertion that matters throughout is that a request with no parameters,
 * or with an unusable one, behaves exactly as it did before any of this existed.
 * A filter that changed the default response would be a contract break, so
 * "ignored" is asserted as a positive outcome rather than as a fallback.
 */
class ReviewFilterSortTest extends TestCase
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
            'LRV' => 'listing_review',
        ][$prefix];

        $column = "{$prefix}_ID";

        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where($column, $id)->exists());

        return $id;
    }

    private function makeUser(string $name, string $email, string $status = 'ACTIVE'): User
    {
        return User::create([
            'USR_ID' => $this->id('USR'),
            'USR_NAME' => $name,
            'USR_EMAIL' => $email,
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0917'.str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_IS_SELLER' => 0,
            'USR_STATUS' => $status,
            'USR_CREATED_AT' => now(),
        ]);
    }

    private function categoryId(): string
    {
        return \App\Models\CropCategory::first()?->CAT_ID
            ?? \App\Models\CropCategory::create([
                'CAT_ID' => $this->id('CAT'),
                'CAT_NAME' => 'Vegetables',
            ])->CAT_ID;
    }

    /** A listing owned by somebody else, so the seeded reviewers are buyers. */
    private function makeListing(): Listing
    {
        $seller = $this->makeUser('React A', 'reacta@test.local');
        $buyer = \App\Models\Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $seller->USR_ID]);
        $farmer = \App\Models\Farmer::create(['FMR_ID' => $this->id('FMR'), 'BUY_ID' => $buyer->BUY_ID]);
        $farm = \App\Models\Farm::create([
            'FRM_ID' => $this->id('FRM'),
            'FRM_NAME' => 'React A Farm',
            'FRM_BARANGAY' => 'Sudlon II',
            'FRM_LATITUDE' => 10.30,
            'FRM_LONGITUDE' => 123.89,
            'FRM_CREATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
        ]);

        return Listing::create([
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
    }

    /**
     * Seeds a review with an explicit age.
     *
     * Created-at is settable because every sort here is defined by it, and
     * seeding everything at now() would make "newest first" indistinguishable
     * from "arbitrary order" — a test that passes for the wrong reason.
     */
    private function seedReview(
        Listing $listing,
        User $author,
        int $rating,
        ?string $comment = null,
        string $status = ListingReview::STATUS_VISIBLE,
        ?string $createdAt = null
    ): ListingReview {
        $review = ListingReview::create([
            'LRV_ID' => $this->id('LRV'),
            'LST_ID' => $listing->LST_ID,
            'USR_ID' => $author->USR_ID,
            'LRV_RATING' => $rating,
            'LRV_COMMENT' => $comment,
            'LRV_STATUS' => $status,
            'LRV_CREATED_AT' => $createdAt ?? now(),
            'LRV_UPDATED_AT' => $createdAt ?? now(),
        ]);

        return $review;
    }

    /**
     * Not named get(): Laravel's TestCase already has a public get(), and a
     * private override of it is a fatal access-level error rather than a
     * confusing test failure.
     */
    private function fetchReviews(Listing $listing, string $query = '')
    {
        return $this->getJson("/api/listings/{$listing->LST_ID}/reviews{$query}");
    }

    /** Ratings of the returned rows, in the order the endpoint returned them. */
    private function ratingsInOrder($response): array
    {
        return collect($response->json('reviews'))
            ->map(fn ($review) => $review['rating'])
            ->values()
            ->all();
    }

    // ------------------------------------------------------------ rating filter

    public function test_rating_filter_returns_only_that_star_count(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('A One', 'a1@test.local'), 1);
        $this->seedReview($listing, $this->makeUser('A Two', 'a2@test.local'), 4, 'Nice');
        $this->seedReview($listing, $this->makeUser('A Three', 'a3@test.local'), 4, 'Also nice');
        $this->seedReview($listing, $this->makeUser('A Four', 'a4@test.local'), 5);

        $response = $this->fetchReviews($listing, '?rating=4');

        $response->assertOk();
        $this->assertSame([4, 4], $this->ratingsInOrder($response));
    }

    public function test_rating_filter_of_one_star_returns_only_one_star_reviews(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('B One', 'b1@test.local'), 1, 'Bad');
        $this->seedReview($listing, $this->makeUser('B Two', 'b2@test.local'), 3);

        $response = $this->fetchReviews($listing, '?rating=1');

        $response->assertOk();
        $this->assertSame([1], $this->ratingsInOrder($response));
    }

    /**
     * @dataProvider invalidRatingProvider
     */
    public function test_an_invalid_rating_is_ignored_and_the_list_is_unfiltered(mixed $value): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('C One', 'c1@test.local'), 1);
        $this->seedReview($listing, $this->makeUser('C Two', 'c2@test.local'), 5, 'Great');

        $response = $this->fetchReviews($listing, '?rating=' . rawurlencode((string) $value));

        // Not a 4xx: a bad parameter from a stale client must not blank a list
        // the buyer is entitled to read. Sorting the two rows newest-first first
        // so the comparison is about the filter, not the order.
        $response->assertOk();
        $this->assertCount(2, $response->json('reviews'));
        $this->assertSame([5, 1], $this->ratingsInOrder($response));
    }

    public static function invalidRatingProvider(): array
    {
        return [
            'zero' => [0],
            'six' => [6],
            'negative' => [-3],
            'not a number' => ['abc'],
            'trailing letters' => ['4abc'],
            'empty' => [''],
        ];
    }

    public function test_a_numeric_string_rating_is_honoured(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('D One', 'd1@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('D Two', 'd2@test.local'), 3);

        $response = $this->fetchReviews($listing, '?rating=5');

        $response->assertOk();
        $this->assertSame([5], $this->ratingsInOrder($response));
    }

    // --------------------------------------------------------- comment filter

    public function test_with_comment_true_returns_only_reviews_with_a_comment(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('E One', 'e1@test.local'), 5, 'Worth it');
        $this->seedReview($listing, $this->makeUser('E Two', 'e2@test.local'), 5);

        $response = $this->fetchReviews($listing, '?with_comment=true');

        $response->assertOk();
        $reviews = $response->json('reviews');
        $this->assertCount(1, $reviews);
        $this->assertSame('Worth it', $reviews[0]['comment']);
    }

    public function test_with_comment_false_returns_only_bare_star_reviews(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('F One', 'f1@test.local'), 5, 'Worth it');
        $this->seedReview($listing, $this->makeUser('F Two', 'f2@test.local'), 4);
        $this->seedReview($listing, $this->makeUser('F Three', 'f3@test.local'), 2);

        $response = $this->fetchReviews($listing, '?with_comment=false');

        $response->assertOk();
        $this->assertCount(2, $response->json('reviews'));
        foreach ($response->json('reviews') as $review) {
            $this->assertNull($review['comment']);
        }
    }

    public function test_an_absent_with_comment_returns_both_kinds(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('G One', 'g1@test.local'), 5, 'Worth it');
        $this->seedReview($listing, $this->makeUser('G Two', 'g2@test.local'), 4);

        $response = $this->fetchReviews($listing);

        $response->assertOk();
        $this->assertCount(2, $response->json('reviews'));
    }

    public function test_the_two_filters_combine(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('H One', 'h1@test.local'), 4, 'Four with words');
        $this->seedReview($listing, $this->makeUser('H Two', 'h2@test.local'), 4);
        $this->seedReview($listing, $this->makeUser('H Three', 'h3@test.local'), 5, 'Five with words');

        $response = $this->fetchReviews($listing, '?rating=4&with_comment=true');

        $response->assertOk();
        $this->assertSame([4], $this->ratingsInOrder($response));
        $this->assertSame('Four with words', $response->json('reviews.0.comment'));
    }

    public function test_an_unusable_with_comment_value_is_ignored(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('I One', 'i1@test.local'), 5, 'Worth it');
        $this->seedReview($listing, $this->makeUser('I Two', 'i2@test.local'), 4);

        $response = $this->fetchReviews($listing, '?with_comment=maybe');

        $response->assertOk();
        $this->assertCount(2, $response->json('reviews'));
    }

    // ------------------------------------------------------------------- sort

    public function test_sort_newest_first_orders_by_created_at_descending(): void
    {
        $listing = $this->makeListing();

        $old = $this->seedReview($listing, $this->makeUser('J Old', 'j1@test.local'), 1, null, ListingReview::STATUS_VISIBLE, '2026-01-01 10:00:00.000000');
        $mid = $this->seedReview($listing, $this->makeUser('J Mid', 'j2@test.local'), 5, null, ListingReview::STATUS_VISIBLE, '2026-02-01 10:00:00.000000');
        $new = $this->seedReview($listing, $this->makeUser('J New', 'j3@test.local'), 3, null, ListingReview::STATUS_VISIBLE, '2026-03-01 10:00:00.000000');

        $response = $this->fetchReviews($listing, '?sort=newest');

        $response->assertOk();
        $this->assertSame(
            [$new->LRV_ID, $mid->LRV_ID, $old->LRV_ID],
            collect($response->json('reviews'))->pluck('id')->all()
        );
    }

    public function test_no_sort_parameter_keeps_the_existing_newest_first_order(): void
    {
        $listing = $this->makeListing();

        $old = $this->seedReview($listing, $this->makeUser('K Old', 'k1@test.local'), 5, null, ListingReview::STATUS_VISIBLE, '2026-01-01 10:00:00.000000');
        $new = $this->seedReview($listing, $this->makeUser('K New', 'k2@test.local'), 1, null, ListingReview::STATUS_VISIBLE, '2026-03-01 10:00:00.000000');

        $response = $this->fetchReviews($listing);

        $response->assertOk();
        $this->assertSame(
            [$new->LRV_ID, $old->LRV_ID],
            collect($response->json('reviews'))->pluck('id')->all()
        );
    }

    /**
     * The ordering the product detail preview's top three rely on: rating
     * first, then reviews that left words, then newest.
     */
    public function test_sort_best_prefers_high_rating_then_commented_then_newest(): void
    {
        $listing = $this->makeListing();

        $oldCommentedFive = $this->seedReview($listing, $this->makeUser('L One', 'l1@test.local'), 5, 'Excellent', ListingReview::STATUS_VISIBLE, '2026-01-01 10:00:00.000000');
        $newBareFive = $this->seedReview($listing, $this->makeUser('L Two', 'l2@test.local'), 5, null, ListingReview::STATUS_VISIBLE, '2026-03-01 10:00:00.000000');
        $newCommentedFour = $this->seedReview($listing, $this->makeUser('L Three', 'l3@test.local'), 4, 'Good', ListingReview::STATUS_VISIBLE, '2026-03-01 10:00:00.000000');
        $newCommentedOne = $this->seedReview($listing, $this->makeUser('L Four', 'l4@test.local'), 1, 'Not for me', ListingReview::STATUS_VISIBLE, '2026-03-01 10:00:00.000000');

        $response = $this->fetchReviews($listing, '?sort=best');

        $response->assertOk();
        $this->assertSame(
            [
                $oldCommentedFive->LRV_ID,
                $newBareFive->LRV_ID,
                $newCommentedFour->LRV_ID,
                $newCommentedOne->LRV_ID,
            ],
            collect($response->json('reviews'))->pluck('id')->all()
        );
    }

    public function test_sort_highest_ignores_whether_a_comment_was_left(): void
    {
        $listing = $this->makeListing();

        $bare = $this->seedReview($listing, $this->makeUser('M One', 'm1@test.local'), 5, null, ListingReview::STATUS_VISIBLE, '2026-01-01 10:00:00.000000');
        $commented = $this->seedReview($listing, $this->makeUser('M Two', 'm2@test.local'), 5, 'Great', ListingReview::STATUS_VISIBLE, '2026-03-01 10:00:00.000000');

        $response = $this->fetchReviews($listing, '?sort=highest');

        $response->assertOk();
        // Rating ties, so the tiebreak is newest — the bare one is older and
        // must come second. "highest" is deliberately not "best".
        $this->assertSame(
            [$commented->LRV_ID, $bare->LRV_ID],
            collect($response->json('reviews'))->pluck('id')->all()
        );
    }

    public function test_sort_lowest_puts_the_worst_rating_first(): void
    {
        $listing = $this->makeListing();

        $five = $this->seedReview($listing, $this->makeUser('N One', 'n1@test.local'), 5);
        $one = $this->seedReview($listing, $this->makeUser('N Two', 'n2@test.local'), 1);
        $three = $this->seedReview($listing, $this->makeUser('N Three', 'n3@test.local'), 3);

        $response = $this->fetchReviews($listing, '?sort=lowest');

        $response->assertOk();
        $this->assertSame([1, 3, 5], $this->ratingsInOrder($response));
        $this->assertSame([$one->LRV_ID, $three->LRV_ID, $five->LRV_ID], collect($response->json('reviews'))->pluck('id')->all());
    }

    public function test_an_unknown_sort_falls_back_to_newest_rather_than_failing(): void
    {
        $listing = $this->makeListing();

        $old = $this->seedReview($listing, $this->makeUser('O Old', 'o1@test.local'), 5, null, ListingReview::STATUS_VISIBLE, '2026-01-01 10:00:00.000000');
        $new = $this->seedReview($listing, $this->makeUser('O New', 'o2@test.local'), 1, null, ListingReview::STATUS_VISIBLE, '2026-03-01 10:00:00.000000');

        $response = $this->fetchReviews($listing, '?sort=sideways');

        $response->assertOk();
        $this->assertSame(
            [$new->LRV_ID, $old->LRV_ID],
            collect($response->json('reviews'))->pluck('id')->all()
        );
    }

    public function test_sort_works_together_with_a_filter(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('P One', 'p1@test.local'), 4, 'a', ListingReview::STATUS_VISIBLE, '2026-01-01 10:00:00.000000');
        $this->seedReview($listing, $this->makeUser('P Two', 'p2@test.local'), 4, 'b', ListingReview::STATUS_VISIBLE, '2026-02-01 10:00:00.000000');
        $this->seedReview($listing, $this->makeUser('P Three', 'p3@test.local'), 5, 'c', ListingReview::STATUS_VISIBLE, '2026-03-01 10:00:00.000000');

        $response = $this->fetchReviews($listing, '?rating=4&sort=lowest');

        // Only the two 4s, and ties broken newest-first: P Two, not P One.
        $response->assertOk();
        $this->assertSame([4, 4], $this->ratingsInOrder($response));
        $this->assertSame('b', $response->json('reviews.0.comment'));
    }

    // ------------------------------------------------------------- pagination

    public function test_pagination_reports_the_filtered_total_not_the_visible_total(): void
    {
        $listing = $this->makeListing();

        for ($i = 0; $i < 3; $i++) {
            $this->seedReview($listing, $this->makeUser("Q Five {$i}", "q5{$i}@test.local"), 5);
        }
        for ($i = 0; $i < 2; $i++) {
            $this->seedReview($listing, $this->makeUser("Q One {$i}", "q1{$i}@test.local"), 1);
        }

        $response = $this->fetchReviews($listing, '?rating=1&per_page=1');

        $response->assertOk();
        $this->assertCount(1, $response->json('reviews'));
        $this->assertSame(2, $response->json('total'));
        $this->assertSame(2, $response->json('last_page'));
        // The unfiltered count is still 5: the header must not shrink because a
        // filter is on.
        $this->assertSame(5, $response->json('summary.count'));
    }

    public function test_page_two_under_a_filter_returns_the_next_matching_slice(): void
    {
        $listing = $this->makeListing();

        $older = $this->seedReview($listing, $this->makeUser('R Old', 'r1@test.local'), 4, 'older', ListingReview::STATUS_VISIBLE, '2026-01-01 10:00:00.000000');
        $newer = $this->seedReview($listing, $this->makeUser('R New', 'r2@test.local'), 4, 'newer', ListingReview::STATUS_VISIBLE, '2026-02-01 10:00:00.000000');

        $response = $this->fetchReviews($listing, '?rating=4&sort=newest&per_page=1&page=2');

        $response->assertOk();
        $this->assertSame([$older->LRV_ID], collect($response->json('reviews'))->pluck('id')->all());
        $this->assertNotSame($newer->LRV_ID, $older->LRV_ID);
    }

    // -------------------------------------------------------------- visibility

    public function test_a_hidden_review_is_never_returned_even_when_it_matches_the_filter(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('S One', 's1@test.local'), 5, 'kept', ListingReview::STATUS_VISIBLE);
        $this->seedReview($listing, $this->makeUser('S Two', 's2@test.local'), 5, 'hidden', ListingReview::STATUS_HIDDEN);

        $response = $this->fetchReviews($listing, '?rating=5&sort=best');

        $response->assertOk();
        $reviews = $response->json('reviews');
        $this->assertCount(1, $reviews);
        $this->assertSame('kept', $reviews[0]['comment']);
    }

    public function test_a_hidden_review_with_the_only_five_star_rating_cannot_be_narrowed_to(): void
    {
        // The rating filter must never be a way to probe for hidden rows: with
        // every visible review excluded by the filter, the response is empty.
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('T One', 't1@test.local'), 3);
        $this->seedReview($listing, $this->makeUser('T Two', 't2@test.local'), 1, null, ListingReview::STATUS_HIDDEN);

        $response = $this->fetchReviews($listing, '?rating=1');

        $response->assertOk();
        $this->assertSame([], $response->json('reviews'));
        $this->assertSame(0, $response->json('total'));
    }

    public function test_with_comment_true_cannot_reveal_a_hidden_review(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('U One', 'u1@test.local'), 3);
        $this->seedReview($listing, $this->makeUser('U Two', 'u2@test.local'), 3, 'hidden words', ListingReview::STATUS_HIDDEN);

        $response = $this->fetchReviews($listing, '?with_comment=true');

        $response->assertOk();
        $this->assertCount(0, $response->json('reviews'));
    }

    // --------------------------------------------------------------- breakdown

    public function test_rating_breakdown_counts_every_visible_review(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('V One', 'v1@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('V Two', 'v2@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('V Three', 'v3@test.local'), 4);
        $this->seedReview($listing, $this->makeUser('V Four', 'v4@test.local'), 2);

        $response = $this->fetchReviews($listing);

        $response->assertOk();
        $response->assertJsonPath('summary.rating_breakdown', [
            '1' => 0,
            '2' => 1,
            '3' => 0,
            '4' => 1,
            '5' => 2,
        ]);
    }

    public function test_rating_breakdown_is_unaffected_by_the_rating_filter(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('W One', 'w1@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('W Two', 'w2@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('W Three', 'w3@test.local'), 4);
        $this->seedReview($listing, $this->makeUser('W Four', 'w4@test.local'), 1);

        $response = $this->fetchReviews($listing, '?rating=5');

        $response->assertOk();
        // Only the two 5s are listed, but the chip counts still describe the
        // whole listing — otherwise the chips the buyer taps would change the
        // numbers printed beside them.
        $this->assertCount(2, $response->json('reviews'));
        $this->assertSame([5, 5], $this->ratingsInOrder($response));
        $response->assertJsonPath('summary.rating_breakdown', [
            '1' => 1,
            '2' => 0,
            '3' => 0,
            '4' => 1,
            '5' => 2,
        ]);
    }

    public function test_rating_breakdown_is_unaffected_by_with_comment(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('X One', 'x1@test.local'), 5, 'words');
        $this->seedReview($listing, $this->makeUser('X Two', 'x2@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('X Three', 'x3@test.local'), 3);

        $response = $this->fetchReviews($listing, '?with_comment=true');

        $response->assertOk();
        $response->assertJsonPath('summary.rating_breakdown', [
            '1' => 0,
            '2' => 0,
            '3' => 1,
            '4' => 0,
            '5' => 2,
        ]);
    }

    public function test_rating_breakdown_counts_only_visible_reviews(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('Y One', 'y1@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('Y Two', 'y2@test.local'), 5, null, ListingReview::STATUS_HIDDEN);
        $this->seedReview($listing, $this->makeUser('Y Three', 'y3@test.local'), 1, null, ListingReview::STATUS_HIDDEN);

        $response = $this->fetchReviews($listing);

        $response->assertOk();
        // Hidden rows are out of the average and out of the counts together.
        $response->assertJsonPath('summary.rating_breakdown', [
            '1' => 0,
            '2' => 0,
            '3' => 0,
            '4' => 0,
            '5' => 1,
        ]);
        $this->assertSame(1, $response->json('summary.count'));
        // assertEquals, not assertSame: PHP's json_encode drops the '.0' from a
        // whole 5.0, so the decoded value is the int 5. The endpoint still sends
        // a number; only its JSON spelling differs.
        $this->assertEquals(5.0, $response->json('summary.average'));
    }

    public function test_rating_breakdown_is_all_zeroes_for_an_unreviewed_listing(): void
    {
        $listing = $this->makeListing();

        $response = $this->fetchReviews($listing);

        $response->assertOk();
        // Every key present with 0, so the app never has to guard a missing
        // index just to decide whether to print a count.
        $response->assertJsonPath('summary.rating_breakdown', [
            '1' => 0,
            '2' => 0,
            '3' => 0,
            '4' => 0,
            '5' => 0,
        ]);
        $this->assertNull($response->json('summary.average'));
    }

    public function test_summary_average_ignores_the_active_filter(): void
    {
        $listing = $this->makeListing();

        // A 3.9 listing that looks like a 5.0 the moment a filter is applied is
        // the exact failure this guards.
        $this->seedReview($listing, $this->makeUser('Z One', 'z1@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('Z Two', 'z2@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('Z Three', 'z3@test.local'), 4);
        $this->seedReview($listing, $this->makeUser('Z Four', 'z4@test.local'), 3);

        $unfiltered = $this->fetchReviews($listing);
        $filtered = $this->fetchReviews($listing, '?rating=5');

        $unfiltered->assertOk();
        $filtered->assertOk();

        $this->assertSame(4.3, $unfiltered->json('summary.average'));
        // Not 5.0, even though every listed row is a 5.
        $this->assertSame(4.3, $filtered->json('summary.average'));
        $this->assertSame(4, $filtered->json('summary.count'));
    }

    // ----------------------------------------------------------------- my_review

    public function test_my_review_is_returned_even_when_the_filter_excludes_it(): void
    {
        $listing = $this->makeListing();
        $buyer = $this->makeUser('Own Author', 'own@test.local');

        $mine = $this->seedReview($listing, $buyer, 2, 'My own two stars');
        $this->seedReview($listing, $this->makeUser('Z Other', 'other@test.local'), 5, 'A five');

        $response = $this->actingAs($buyer, 'sanctum')
            ->getJson("/api/listings/{$listing->LST_ID}/reviews?rating=5");

        $response->assertOk();
        // The list is filtered to the other review...
        $this->assertSame(['A five'], collect($response->json('reviews'))->pluck('comment')->all());
        // ...but the caller's own row still comes back, or "Edit your review"
        // would vanish the moment they opened a filter.
        $this->assertSame($mine->LRV_ID, $response->json('my_review.id'));
        $this->assertTrue($response->json('my_review.is_mine'));
    }

    public function test_my_review_is_returned_when_with_comment_excludes_it(): void
    {
        $listing = $this->makeListing();
        $buyer = $this->makeUser('Bare Author', 'bare@test.local');

        $mine = $this->seedReview($listing, $buyer, 5);

        $response = $this->actingAs($buyer, 'sanctum')
            ->getJson("/api/listings/{$listing->LST_ID}/reviews?with_comment=true");

        $response->assertOk();
        $this->assertSame([], $response->json('reviews'));
        $this->assertSame($mine->LRV_ID, $response->json('my_review.id'));
    }

    public function test_can_review_is_unchanged_by_the_filters(): void
    {
        $listing = $this->makeListing();
        $buyer = $this->makeUser('Can Review', 'can@test.local');

        $response = $this->actingAs($buyer, 'sanctum')
            ->getJson("/api/listings/{$listing->LST_ID}/reviews?rating=5&sort=lowest&with_comment=false");

        $response->assertOk();
        $response->assertJsonPath('can_review', true);
        $response->assertJsonPath('review_blocked_reason', null);
    }

    public function test_own_listing_still_reports_its_own_reason_under_a_filter(): void
    {
        // The seller's blocked reason is computed from the listing, not the
        // filters, so "This is your own listing." survives ?rating=1.
        $seller = $this->makeUser('React A', 'reacta2@test.local');
        $buyer = \App\Models\Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $seller->USR_ID]);
        $farmer = \App\Models\Farmer::create(['FMR_ID' => $this->id('FMR'), 'BUY_ID' => $buyer->BUY_ID]);
        $farm = \App\Models\Farm::create([
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
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
            'FRM_ID' => $farm->FRM_ID,
            'CAT_ID' => $this->categoryId(),
            'LST_CROP_ICON' => 'Carrot',
        ]);

        $response = $this->actingAs($seller, 'sanctum')
            ->getJson("/api/listings/{$listing->LST_ID}/reviews?rating=1");

        $response->assertOk();
        $response->assertJsonPath('can_review', false);
        $response->assertJsonPath('review_blocked_reason', 'This is your own listing.');
    }

    // ------------------------------------------------------- per_page interaction

    public function test_per_page_three_returns_only_three_rows_but_the_full_count(): void
    {
        // What the product detail preview asks for: three rows, and a count
        // describing all of them.
        $listing = $this->makeListing();

        for ($i = 1; $i <= 10; $i++) {
            $this->seedReview(
                $listing,
                $this->makeUser("AA {$i}", "aa{$i}@test.local"),
                5,
                "Review number {$i}",
                ListingReview::STATUS_VISIBLE,
                sprintf('2026-01-%02d 10:00:00.000000', $i)
            );
        }

        $response = $this->fetchReviews($listing, '?sort=best&per_page=3');

        $response->assertOk();
        $this->assertCount(3, $response->json('reviews'));
        $this->assertSame(10, $response->json('total'));
        $this->assertSame(4, $response->json('last_page'));
        // assertEquals, not assertSame: PHP's json_encode drops the '.0' from a
        // whole 5.0, so the decoded value is the int 5. The endpoint still sends
        // a number; only its JSON spelling differs.
        $this->assertEquals(5.0, $response->json('summary.average'));
        $this->assertSame(10, $response->json('summary.count'));
        // All three carry a comment, so "best" put the written ones first and
        // the latest of them leads.
        $this->assertSame('Review number 10', $response->json('reviews.0.comment'));
    }

    public function test_per_page_three_with_a_filter_paginates_the_filtered_set(): void
    {
        $listing = $this->makeListing();

        for ($i = 1; $i <= 6; $i++) {
            $this->seedReview(
                $listing,
                $this->makeUser("BB Five {$i}", "bbf{$i}@test.local"),
                5,
                null,
                ListingReview::STATUS_VISIBLE,
                sprintf('2026-01-%02d 10:00:00.000000', $i)
            );
        }
        for ($i = 1; $i <= 2; $i++) {
            $this->seedReview($listing, $this->makeUser("BB One {$i}", "bbo{$i}@test.local"), 1);
        }

        $response = $this->fetchReviews($listing, '?rating=5&sort=newest&per_page=3');

        $response->assertOk();
        $this->assertCount(3, $response->json('reviews'));
        $this->assertSame(6, $response->json('total'));
        $this->assertSame(2, $response->json('last_page'));
        $this->assertSame(8, $response->json('summary.count'));
    }

    public function test_a_filter_matching_nothing_returns_an_empty_list_not_an_error(): void
    {
        $listing = $this->makeListing();

        $this->seedReview($listing, $this->makeUser('CC One', 'cc1@test.local'), 5);
        $this->seedReview($listing, $this->makeUser('CC Two', 'cc2@test.local'), 5);

        $response = $this->fetchReviews($listing, '?rating=1&with_comment=true');

        // The empty state is a normal outcome, so the app can render it rather
        // than an error. last_page is 1 rather than 0 because there is nothing
        // to page through.
        $response->assertOk();
        $this->assertSame([], $response->json('reviews'));
        $this->assertSame(0, $response->json('total'));
        $this->assertSame(1, $response->json('last_page'));
        // The summary still describes the whole listing.
        $this->assertSame(2, $response->json('summary.count'));
        // assertEquals, not assertSame: PHP's json_encode drops the '.0' from a
        // whole 5.0, so the decoded value is the int 5. The endpoint still sends
        // a number; only its JSON spelling differs.
        $this->assertEquals(5.0, $response->json('summary.average'));
    }
}