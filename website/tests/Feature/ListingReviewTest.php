<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\ListingReview;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The buyer-facing review contract.
 *
 * Rules that have to hold, and why each one is easy to get wrong:
 *
 *  1. Only an ACTIVE account may review. The read endpoint is public, so this
 *     cannot live in middleware without the GET demanding a token.
 *  2. Nobody may review their own listing, reached through the
 *     user -> buyer -> farmer chain rather than by comparing ids on the listing.
 *  3. A REMOVED listing cannot be reviewed. Leaving that to the app would let a
 *     stale client keep writing reviews to a listing that is gone.
 *  4. One review per user per listing, enforced by a UNIQUE key so a retried
 *     submit updates rather than inserting a second row.
 *  5. The public payload never carries an email or a mobile number.
 *  6. A hidden review vanishes from the list AND from the average, because both
 *     read through the same visible() scope.
 *  7. Someone else's review id is a 404, not a 403, so the endpoint is not an
 *     oracle for confirming which ids exist.
 *
 * The schema comes from a committed SQL dump plus migrations, so these run
 * against MySQL (see phpunit.mysql.xml).
 */
class ListingReviewTest extends TestCase
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

    /**
     * A seller's listing: user -> buyer -> farmer -> farm -> listing.
     */
    private function makeListing(string $availability = 'ACTIVE'): array
    {
        $user = $this->makeUser('React A', 'reacta@test.local');
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
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => $availability,
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
            'FRM_ID' => $farm->FRM_ID,
            'CAT_ID' => $this->categoryId(),
            'LST_CROP_ICON' => 'Carrot',
        ]);

        return compact('user', 'buyer', 'farmer', 'farm', 'listing');
    }

    private function makeBuyerUser(string $name = 'Maria Santos', string $email = 'maria@test.local', string $status = 'ACTIVE'): array
    {
        $user = $this->makeUser($name, $email, $status);
        $buyer = Buyer::create(['BUY_ID' => $this->id('BUY'), 'USR_ID' => $user->USR_ID]);

        return compact('user', 'buyer');
    }

    private function categoryId(): string
    {
        return CropCategory::first()?->CAT_ID
            ?? CropCategory::create(['CAT_ID' => $this->id('CAT'), 'CAT_NAME' => 'Vegetables'])->CAT_ID;
    }

    private function review(User $user, Listing $listing, array $payload)
    {
        return $this->actingAs($user, 'sanctum')
            ->postJson("/api/listings/{$listing->LST_ID}/reviews", $payload);
    }

    /**
     * Inserts a review without touching the auth guards.
     *
     * Needed by the read tests: actingAs() sets the authenticated user for the
     * rest of the test, so a later "guest" request would still be treated as
     * that user and the guest branch of the endpoint would never run. Writing
     * the row through the model keeps the guard state clean.
     */
    private function seedReview(Listing $listing, User $author, int $rating, ?string $comment = null, string $status = ListingReview::STATUS_VISIBLE): ListingReview
    {
        return ListingReview::create([
            'LRV_ID' => $this->id('LRV'),
            'LST_ID' => $listing->LST_ID,
            'USR_ID' => $author->USR_ID,
            'LRV_RATING' => $rating,
            'LRV_COMMENT' => $comment,
            'LRV_STATUS' => $status,
            'LRV_CREATED_AT' => now(),
            'LRV_UPDATED_AT' => now(),
        ]);
    }

    // ------------------------------------------------------------ happy path

    public function test_a_buyer_can_write_a_review_and_the_summary_reflects_it(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $response = $this->review($buyer['user'], $seller['listing'], [
            'rating' => 5,
            'comment' => 'Fresh carrots, very good quality.',
        ]);

        $response->assertCreated()
            ->assertJsonPath('review.rating', 5)
            ->assertJsonPath('review.comment', 'Fresh carrots, very good quality.')
            ->assertJsonPath('review.is_mine', true)
            // The review was just written, so the returned average must already
            // include it — the app refreshes the header from this one payload.
            // Cast to float: json_encode() drops the ".0" from a whole number,
            // so `average` arrives as the int 5 rather than the float 5.0.
            ->assertJsonPath('summary.count', 1);

        $this->assertSame(5.0, (float) $response->json('summary.average'));

        $this->assertDatabaseHas('listing_review', [
            'LST_ID' => $seller['listing']->LST_ID,
            'USR_ID' => $buyer['user']->USR_ID,
            'LRV_RATING' => 5,
            'LRV_STATUS' => ListingReview::STATUS_VISIBLE,
        ]);
    }

    public function test_the_comment_is_optional_and_a_rating_only_review_is_accepted(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], ['rating' => 4])
            ->assertCreated()
            ->assertJsonPath('review.comment', null);
    }

    public function test_the_comment_is_trimmed_before_it_is_stored(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], [
            'rating' => 3,
            'comment' => "   \n  Nice and fresh.  \t ",
        ])->assertCreated()
            ->assertJsonPath('review.comment', 'Nice and fresh.');

        $this->assertDatabaseHas('listing_review', [
            'LST_ID' => $seller['listing']->LST_ID,
            'LRV_COMMENT' => 'Nice and fresh.',
        ]);
    }

    // ------------------------------------------------------- who may review

    public function test_an_inactive_account_cannot_write_a_review(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser('Blocked User', 'blocked@test.local', 'DEACTIVATED');

        $this->review($buyer['user'], $seller['listing'], ['rating' => 5])
            ->assertForbidden();

        $this->assertDatabaseCount('listing_review', 0);
    }

    public function test_a_guest_is_asked_to_sign_in_rather_than_told_the_rule(): void
    {
        $seller = $this->makeListing();

        $this->postJson("/api/listings/{$seller['listing']->LST_ID}/reviews", ['rating' => 5])
            ->assertUnauthorized();
    }

    public function test_the_seller_cannot_review_their_own_listing(): void
    {
        $seller = $this->makeListing();

        // The listing's FMR_ID points at a farmer that hangs off a buyer that
        // points back at the seller's user, so this is the own-listing guard
        // and not a simple id comparison.
        $this->review($seller['user'], $seller['listing'], ['rating' => 5])->assertForbidden();

        $this->assertDatabaseCount('listing_review', 0);
    }

    public function test_a_removed_listing_cannot_be_reviewed(): void
    {
        $seller = $this->makeListing('REMOVED');
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], ['rating' => 5])->assertForbidden();

        $this->assertDatabaseCount('listing_review', 0);
    }

    // --------------------------------------------------------- rating bounds

    /**
     * @dataProvider outOfRangeRatings
     */
    public function test_a_rating_outside_one_to_five_is_rejected($rating): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], ['rating' => $rating])
            ->assertStatus(422)
            ->assertJsonValidationErrors('rating');

        $this->assertDatabaseCount('listing_review', 0);
    }

    public static function outOfRangeRatings(): array
    {
        return [
            'zero' => [0],
            'six' => [6],
            'negative' => [-1],
            'fractional' => [2.5],
        ];
    }

    public function test_a_rating_is_required(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], ['comment' => 'No stars given'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('rating');
    }

    public function test_a_comment_longer_than_three_hundred_characters_is_rejected(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], [
            'rating' => 4,
            'comment' => str_repeat('a', 301),
        ])->assertStatus(422)->assertJsonValidationErrors('comment');

        $this->assertDatabaseCount('listing_review', 0);
    }

    // --------------------------------------------------------- one per user

    public function test_writing_a_second_review_updates_the_first_instead_of_adding_a_row(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], ['rating' => 2, 'comment' => 'Wrong first take'])
            ->assertCreated();

        $first = ListingReview::first();

        $this->review($buyer['user'], $seller['listing'], ['rating' => 5, 'comment' => 'On reflection, great'])
            ->assertOk()
            ->assertJsonPath('review.id', $first->LRV_ID)
            ->assertJsonPath('review.rating', 5)
            // Still one row, and the count has not been inflated to 2.
            ->assertJsonPath('summary.count', 1);

        $this->assertDatabaseCount('listing_review', 1);
        $this->assertDatabaseHas('listing_review', [
            'LRV_ID' => $first->LRV_ID,
            'LRV_RATING' => 5,
            'LRV_COMMENT' => 'On reflection, great',
        ]);
    }

    public function test_updating_a_review_keeps_the_id_and_the_original_created_at(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], ['rating' => 2]);
        $first = ListingReview::first();
        $createdAt = $first->LRV_CREATED_AT;

        $this->travel(5)->minutes();

        $this->review($buyer['user'], $seller['listing'], ['rating' => 4])->assertOk();

        $first->refresh();
        $this->assertSame(4, (int) $first->LRV_RATING);
        // An edit is not a new review: the date the buyer first wrote it has to
        // stay put or the listing's history reorders under them.
        $this->assertTrue($createdAt->equalTo($first->LRV_CREATED_AT));
        $this->assertTrue($first->LRV_UPDATED_AT->greaterThan($first->LRV_CREATED_AT));
    }

    // ------------------------------------------------------------- deleting

    public function test_a_buyer_can_delete_their_own_review(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], ['rating' => 1, 'comment' => 'Bad'])
            ->assertCreated();

        $this->actingAs($buyer['user'], 'sanctum')
            ->deleteJson("/api/listings/{$seller['listing']->LST_ID}/reviews")
            ->assertOk()
            // The average has to be recomputed in the same response, or the card
            // keeps showing a rating for a review that no longer exists.
            ->assertJsonPath('summary.count', 0)
            ->assertJsonPath('summary.average', null);

        $this->assertDatabaseCount('listing_review', 0);
    }

    public function test_deleting_a_review_that_does_not_exist_is_a_404(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->actingAs($buyer['user'], 'sanctum')
            ->deleteJson("/api/listings/{$seller['listing']->LST_ID}/reviews")
            ->assertNotFound();
    }

    public function test_a_buyer_cannot_delete_another_buyers_review(): void
    {
        $seller = $this->makeListing();
        $author = $this->makeBuyerUser('Author One', 'author1@test.local');
        $stranger = $this->makeBuyerUser('Nosy Person', 'nosy@test.local');

        $this->review($author['user'], $seller['listing'], ['rating' => 3])->assertCreated();

        // 404 rather than 403: a 403 would confirm the id belongs to someone.
        $this->actingAs($stranger['user'], 'sanctum')
            ->deleteJson("/api/listings/{$seller['listing']->LST_ID}/reviews")
            ->assertNotFound();

        $this->assertDatabaseCount('listing_review', 1);
    }

    // ------------------------------------------------------ reading reviews

    public function test_the_review_list_is_public_and_hides_contact_details(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser('Maria Santos', 'maria@test.local');

        $this->seedReview($seller['listing'], $buyer['user'], 5, 'Excellent');

        // No token at all: reviews are shown on the public listing page.
        $response = $this->getJson("/api/listings/{$seller['listing']->LST_ID}/reviews");

        $response->assertOk()
            ->assertJsonPath('reviews.0.rating', 5)
            ->assertJsonPath('reviews.0.reviewer', 'Maria S.')
            // A guest has nothing to edit and nothing to write.
            ->assertJsonPath('my_review', null)
            ->assertJsonPath('can_review', false)
            ->assertJsonPath('summary.count', 1);

        // The whole payload, serialised, must not carry the email or the mobile.
        $body = $response->getContent();
        $this->assertStringNotContainsString('maria@test.local', $body);
        $this->assertStringNotContainsString('0917', $body);
    }

    public function test_a_buyer_sees_their_own_review_prefilled(): void
    {
        $seller = $this->makeListing();
        $buyer = $this->makeBuyerUser();

        $this->review($buyer['user'], $seller['listing'], ['rating' => 4, 'comment' => 'Mine'])
            ->assertCreated();

        $this->actingAs($buyer['user'], 'sanctum')
            ->getJson("/api/listings/{$seller['listing']->LST_ID}/reviews")
            ->assertOk()
            // The app opens the existing review for editing off this value
            // rather than presenting an empty sheet.
            ->assertJsonPath('my_review.rating', 4)
            ->assertJsonPath('my_review.comment', 'Mine')
            ->assertJsonPath('my_review.is_mine', true)
            // Having reviewed already does not block a second write: the rule
            // is one row per user, and the write is an update.
            ->assertJsonPath('can_review', true);
    }

    public function test_the_list_is_paginated_newest_first_and_the_page_size_is_clamped(): void
    {
        $seller = $this->makeListing();

        foreach ([[5, 'first'], [4, 'second'], [3, 'third'], [2, 'fourth'], [1, 'fifth']] as [$rating, $comment]) {
            $this->review(
                $this->makeBuyerUser("Buyer {$comment}", str_replace(' ', '', $comment).'@test.local')['user'],
                $seller['listing'],
                ['rating' => $rating, 'comment' => $comment]
            )->assertCreated();
        }

        $this->getJson("/api/listings/{$seller['listing']->LST_ID}/reviews?per_page=2")
            ->assertOk()
            ->assertJsonCount(2, 'reviews')
            // Newest first: the last one written is 'fifth'.
            ->assertJsonPath('reviews.0.comment', 'fifth')
            ->assertJsonPath('reviews.1.comment', 'fourth')
            ->assertJsonPath('summary.count', 5);

        // ?per_page= is clamped to 50 rather than honoured, so it cannot be
        // used to ask for the whole table in one response. The clamped value
        // is echoed back, which is what proves the cap was applied.
        $clamped = $this->getJson("/api/listings/{$seller['listing']->LST_ID}/reviews?per_page=500");
        $clamped->assertOk()->assertJsonPath('per_page', 50);

        $this->assertSame(5, count($clamped->json('reviews')));
    }

    public function test_the_average_is_rounded_to_one_decimal(): void
    {
        $seller = $this->makeListing();

        // 4 + 4 + 5 = 13/3 = 4.333...
        foreach ([4, 4, 5] as $index => $rating) {
            $this->review(
                $this->makeBuyerUser("Buyer {$index}", "buyer{$index}@test.local")['user'],
                $seller['listing'],
                ['rating' => $rating]
            )->assertCreated();
        }

        $this->getJson("/api/listings/{$seller['listing']->LST_ID}/reviews")
            ->assertOk()
            ->assertJsonPath('summary.average', 4.3)
            ->assertJsonPath('summary.count', 3);
    }

    public function test_reading_reviews_for_a_listing_that_does_not_exist_is_a_404(): void
    {
        $this->getJson('/api/listings/ZZZZZZ/reviews')->assertNotFound();
    }

    // ---------------------------------------------------------- moderation

    public function test_a_hidden_review_leaves_the_list_and_the_average_but_the_row_survives(): void
    {
        $seller = $this->makeListing();

        $this->review($this->makeBuyerUser('Keep Me', 'keep@test.local')['user'], $seller['listing'], ['rating' => 5])->assertCreated();
        $this->review($this->makeBuyerUser('Hide Me', 'hide@test.local')['user'], $seller['listing'], [
            'rating' => 1,
            'comment' => 'A one star that a moderator will hide',
        ])->assertCreated();

        $doomed = ListingReview::where('LRV_COMMENT', 'A one star that a moderator will hide')->firstOrFail();
        $doomed->LRV_STATUS = ListingReview::STATUS_HIDDEN;
        $doomed->save();

        $response = $this->getJson("/api/listings/{$seller['listing']->LST_ID}/reviews");
        $response->assertOk()
            ->assertJsonCount(1, 'reviews')
            ->assertJsonPath('reviews.0.reviewer', 'Keep M.')
            // Count AND average both come from visible() only, so a hidden
            // one-star review cannot drag the listing down.
            ->assertJsonPath('summary.count', 1);

        $this->assertSame(5.0, (float) $response->json('summary.average'));

        // Hidden means moderation, not deletion: the row is still there.
        $this->assertDatabaseHas('listing_review', [
            'LRV_ID' => $doomed->LRV_ID,
            'LRV_STATUS' => ListingReview::STATUS_HIDDEN,
        ]);
    }

    public function test_unhiding_puts_a_review_back_into_the_list_and_the_average(): void
    {
        $seller = $this->makeListing();
        $this->review($this->makeBuyerUser('Bring Back', 'back@test.local')['user'], $seller['listing'], [
            'rating' => 1,
            'comment' => 'Shown again',
        ])->assertCreated();

        $review = ListingReview::firstOrFail();
        $review->LRV_STATUS = ListingReview::STATUS_HIDDEN;
        $review->save();

        $review->LRV_STATUS = ListingReview::STATUS_VISIBLE;
        $review->save();

        $this->getJson("/api/listings/{$seller['listing']->LST_ID}/reviews")
            ->assertOk()
            ->assertJsonPath('reviews.0.comment', 'Shown again')
            ->assertJsonPath('summary.count', 1);
    }

    // ------------------------------------------- rating on listing payloads

    public function test_the_feed_carries_the_rating_summary_in_the_same_query(): void
    {
        $seller = $this->makeListing();
        $listingId = $seller['listing']->LST_ID;

        $this->review($this->makeBuyerUser('Rated It', 'rated@test.local')['user'], $seller['listing'], [
            'rating' => 4,
            'comment' => 'Good',
        ])->assertCreated();
        $this->review($this->makeBuyerUser('Rated It Too', 'rated2@test.local')['user'], $seller['listing'], [
            'rating' => 5,
        ])->assertCreated();

        // Hidden rows must not be counted here either. Selected by comment, not by
        // first(): LRV_ID is six random digits, so first() would pick an
        // arbitrary one of the two and the assertion would be a coin toss.
        $hidden = ListingReview::where('LRV_COMMENT', 'Good')->firstOrFail();
        $hidden->LRV_STATUS = ListingReview::STATUS_HIDDEN;
        $hidden->save();

        $response = $this->getJson('/api/listings');
        $response->assertOk();

        $payload = collect($response->json('listings'))
            ->firstWhere('id', $listingId);

        $this->assertNotNull($payload, 'The rated listing should be in the feed payload.');
        // One 5-star review left after hiding the other.
        $this->assertSame(5.0, (float) $payload['rating_average']);
        $this->assertSame(1, (int) $payload['rating_count']);
    }

    public function test_a_listing_with_no_reviews_reports_a_null_average_rather_than_zero(): void
    {
        $this->makeListing();

        $response = $this->getJson('/api/listings');
        $response->assertOk();

        $payload = collect($response->json('listings'))->first();

        // Null, not 0.0: a listing nobody has rated yet is not a zero-star
        // listing, and the app shows no stars at all when this is null.
        $this->assertNull($payload['rating_average']);
        $this->assertSame(0, $payload['rating_count']);
    }

    public function test_the_product_detail_payload_carries_the_rating_summary(): void
    {
        $seller = $this->makeListing();
        $listingId = $seller['listing']->LST_ID;

        $this->review($this->makeBuyerUser('Detail Reader', 'detail@test.local')['user'], $seller['listing'], [
            'rating' => 3,
        ])->assertCreated();

        $response = $this->getJson("/api/listings/{$listingId}");
        $response->assertOk()->assertJsonPath('listing.rating_count', 1);

        $this->assertSame(3.0, (float) $response->json('listing.rating_average'));
    }

    public function test_the_farm_profile_payload_carries_the_rating_summary(): void
    {
        $seller = $this->makeListing();
        $listingId = $seller['listing']->LST_ID;

        $this->review($this->makeBuyerUser('Map Visitor', 'map@test.local')['user'], $seller['listing'], [
            'rating' => 5,
        ])->assertCreated();

        // The map itself lists farms rather than listings, so the rating rides
        // on the profile listings a map pin opens.
        $response = $this->getJson("/api/farms/{$seller['farm']->FRM_ID}/profile");
        $response->assertOk();

        $payload = collect($response->json('listings'))->firstWhere('id', $listingId);

        $this->assertNotNull($payload, 'The farm profile should carry the listing.');
        $this->assertSame(5.0, (float) $payload['rating_average']);
        $this->assertSame(1, (int) $payload['rating_count']);
    }
}