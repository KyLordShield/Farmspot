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
 * The admin Reviews page.
 *
 * What is worth pinning down here is the shape of the moderation, not the
 * styling:
 *
 *  1. Only an ADMIN can open the page or toggle a review. The panel is behind
 *     auth + admin, and a general user must not be able to moderate reviews by
 *     posting to the route directly.
 *  2. Hide and un-hide are the only two actions. There is no create, no edit
 *     and no delete route, so the page cannot rewrite or destroy a buyer's
 *     words.
 *  3. Hiding is reversible and moves the row between the visible and hidden
 *     filters rather than removing it.
 *  4. Hiding changes the listing's rating average immediately, because the
 *     average is computed from visible() rows rather than stored.
 *  5. The page shows first name + last initial only. Rendering the full name
 *     here would make the admin panel the place the privacy rule leaks.
 *
 * Runs against MySQL (see phpunit.mysql.xml).
 */
class ReviewModerationTest extends TestCase
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
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
            'FRM_ID' => $farm->FRM_ID,
            'CAT_ID' => $this->categoryId(),
            'LST_CROP_ICON' => 'Carrot',
        ]);

        return compact('user', 'listing');
    }

    private function categoryId(): string
    {
        return CropCategory::first()?->CAT_ID
            ?? CropCategory::create(['CAT_ID' => $this->id('CAT'), 'CAT_NAME' => 'Vegetables'])->CAT_ID;
    }

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

    // ------------------------------------------------------------- access

    public function test_a_guest_cannot_open_the_reviews_page(): void
    {
        $this->get('/reviews')->assertRedirect('/login');
    }

    public function test_a_general_user_cannot_open_the_reviews_page(): void
    {
        $this->actingAs($this->makeUser())
            ->get('/reviews')
            ->assertForbidden();
    }

    public function test_a_general_user_cannot_hide_a_review_by_posting_to_the_route(): void
    {
        $listing = $this->makeListing();
        $review = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'Author'), 1, 'Spam');

        $this->actingAs($this->makeUser('GENERAL_USER', 'Nosy'))
            ->patch("/reviews/{$review->LRV_ID}/visibility")
            ->assertForbidden();

        $this->assertSame(ListingReview::STATUS_VISIBLE, $review->fresh()->LRV_STATUS);
    }

    public function test_an_admin_can_open_the_page(): void
    {
        $listing = $this->makeListing();
        $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'Maria Santos'), 4, 'Good');

        $this->actingAs($this->makeUser('ADMIN', 'Moderator'))
            ->get('/reviews')
            ->assertOk()
            // First name plus last initial, never the full name.
            ->assertSee('Maria S.')
            ->assertDontSee('Maria Santos');
    }

    // ------------------------------------------------------------- hiding

    public function test_an_admin_can_hide_a_review_and_unhide_it_again(): void
    {
        $listing = $this->makeListing();
        $review = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'Author'), 1, 'Hide me');
        $admin = $this->makeUser('ADMIN', 'Moderator');

        $this->actingAs($admin)
            ->patch("/reviews/{$review->LRV_ID}/visibility")
            ->assertRedirect('/reviews')
            ->assertSessionHas('success');

        $this->assertSame(ListingReview::STATUS_HIDDEN, $review->fresh()->LRV_STATUS);

        // Same route, opposite direction: one button, not two.
        $this->actingAs($admin)
            ->patch("/reviews/{$review->LRV_ID}/visibility")
            ->assertRedirect('/reviews');

        $this->assertSame(ListingReview::STATUS_VISIBLE, $review->fresh()->LRV_STATUS);
    }

    public function test_hiding_moves_the_review_out_of_the_public_list_and_the_average(): void
    {
        $listing = $this->makeListing();
        $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'Keeper'), 5);
        $doomed = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'Doomed'), 1, 'Hide me');

        $this->actingAs($this->makeUser('ADMIN', 'Moderator'))
            ->patch("/reviews/{$doomed->LRV_ID}/visibility");

        $response = $this->getJson("/api/listings/{$listing['listing']->LST_ID}/reviews");
        $response->assertOk()->assertJsonCount(1, 'reviews')->assertJsonPath('summary.count', 1);

        $this->assertSame(5.0, (float) $response->json('summary.average'));
    }

    public function test_hiding_keeps_the_row_so_it_can_be_restored(): void
    {
        $listing = $this->makeListing();
        $review = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'Author'), 2, 'Keep the text');

        $this->actingAs($this->makeUser('ADMIN', 'Moderator'))
            ->patch("/reviews/{$review->LRV_ID}/visibility");

        // Hiding is moderation, not deletion: the words survive so a later
        // decision can be reversed and the history is not rewritten.
        $this->assertDatabaseHas('listing_review', [
            'LRV_ID' => $review->LRV_ID,
            'LRV_COMMENT' => 'Keep the text',
            'LRV_STATUS' => ListingReview::STATUS_HIDDEN,
        ]);
    }

    public function test_hiding_an_unknown_review_reports_not_found(): void
    {
        $this->actingAs($this->makeUser('ADMIN', 'Moderator'))
            ->patch('/reviews/ZZZZZZ/visibility')
            ->assertRedirect('/reviews')
            ->assertSessionHas('error');
    }

    public function test_the_redirect_keeps_the_active_filters(): void
    {
        $listing = $this->makeListing();
        $review = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'Author'), 1, 'x');
        $admin = $this->makeUser('ADMIN', 'Moderator');

        // A moderator working the hidden queue must not be thrown back to an
        // unfiltered page one after each action.
        $this->actingAs($admin)
            ->patch("/reviews/{$review->LRV_ID}/visibility?status=".ListingReview::STATUS_VISIBLE.'&page=2')
            ->assertRedirectContains('status='.ListingReview::STATUS_VISIBLE);

        $this->actingAs($admin)
            ->patch("/reviews/{$review->LRV_ID}/visibility")
            ->assertRedirect('/reviews');
    }

    // ------------------------------------------------------------ filters

    public function test_the_status_filter_splits_visible_from_hidden(): void
    {
        $listing = $this->makeListing();
        $visible = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'A'), 4, 'up');
        $hidden = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'B'), 2, 'down', ListingReview::STATUS_HIDDEN);
        $admin = $this->makeUser('ADMIN', 'Moderator');

        $this->actingAs($admin)
            ->get('/reviews?status=HIDDEN')
            ->assertOk()
            ->assertSee($hidden->LRV_ID)
            // The visible one is filtered out, so its comment must not appear.
            ->assertDontSee($visible->LRV_ID);

        $this->actingAs($admin)
            ->get('/reviews?status=VISIBLE')
            ->assertOk()
            ->assertSee($visible->LRV_ID)
            ->assertDontSee($hidden->LRV_ID);
    }

    public function test_the_rating_filter_narrows_to_one_star_value(): void
    {
        $listing = $this->makeListing();
        $oneStar = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'A'), 1, 'bad');
        $fiveStar = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'B'), 5, 'great');
        $admin = $this->makeUser('ADMIN', 'Moderator');

        $this->actingAs($admin)
            ->get('/reviews?rating=1')
            ->assertOk()
            ->assertSee($oneStar->LRV_ID)
            ->assertDontSee($fiveStar->LRV_ID);
    }

    public function test_the_search_matches_the_reviewer_the_crop_and_the_farm(): void
    {
        $listing = $this->makeListing();
        $mine = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'Maria Santos'), 4, 'mine');
        $other = $this->seedReview(
            $listing['listing'],
            $this->makeUser('GENERAL_USER', 'Someone Else'),
            4,
            'theirs'
        );
        $admin = $this->makeUser('ADMIN', 'Moderator');

        $this->actingAs($admin)
            ->get('/reviews?search=Maria')
            ->assertOk()
            ->assertSee($mine->LRV_ID)
            ->assertDontSee($other->LRV_ID);

        // The listing is a Carrot, and the farm is React A Farm.
        $this->actingAs($admin)
            ->get('/reviews?search=Carrot')
            ->assertOk()
            ->assertSee($mine->LRV_ID);

        $this->actingAs($admin)
            ->get('/reviews?search='.urlencode('React A Farm'))
            ->assertOk()
            ->assertSee($mine->LRV_ID);

        // And the free-text part of a review.
        $this->actingAs($admin)
            ->get('/reviews?search=theirs')
            ->assertOk()
            ->assertSee($other->LRV_ID)
            ->assertDontSee($mine->LRV_ID);
    }

    public function test_an_out_of_range_rating_filter_is_ignored_rather_than_matching_nothing(): void
    {
        $listing = $this->makeListing();
        $review = $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'A'), 4);
        $admin = $this->makeUser('ADMIN', 'Moderator');

        // ?rating=9 is not reachable from the dropdown. Treating it as a real
        // filter would show an empty page and look like the data was lost.
        $this->actingAs($admin)
            ->get('/reviews?rating=9')
            ->assertOk()
            ->assertSee($review->LRV_ID);
    }

    public function test_the_page_reports_how_many_reviews_are_visible_and_hidden(): void
    {
        $listing = $this->makeListing();
        $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'A'), 5);
        $this->seedReview($listing['listing'], $this->makeUser('GENERAL_USER', 'B'), 1, 'x', ListingReview::STATUS_HIDDEN);
        $admin = $this->makeUser('ADMIN', 'Moderator');

        $response = $this->actingAs($admin)->get('/reviews');

        $response->assertOk()
            ->assertSee('Visible to buyers')
            ->assertSee('Hidden');

        $response->assertViewHas('visibleCount', 1);
        $response->assertViewHas('hiddenCount', 1);
    }

    public function test_the_page_never_renders_a_full_name_or_contact_detail(): void
    {
        $listing = $this->makeListing();
        $author = $this->makeUser('GENERAL_USER', 'Maria Santos Rivera');
        $this->seedReview($listing['listing'], $author, 4, 'Nice crop');

        $body = $this->actingAs($this->makeUser('ADMIN', 'Moderator'))
            ->get('/reviews')
            ->getContent();

        $this->assertStringContainsString('Maria R.', $body);
        $this->assertStringNotContainsString('Maria Santos', $body);
        $this->assertStringNotContainsString($author->USR_EMAIL, $body);
        $this->assertStringNotContainsString($author->USR_MOBILE_NUMBER, $body);
    }
}