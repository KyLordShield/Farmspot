<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Insight;
use App\Models\Listing;
use App\Models\Trend;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Admin CRUD for crop categories, driven from the panel on the Listings page.
 *
 * What matters here is not the styling but the three ways this feature can quietly
 * break something a buyer can see:
 *
 *  1. Authorisation. The routes sit inside the auth + admin group, so a general
 *     user must get 403 rather than a working create form they should not have.
 *
 *  2. The generated ID. CAT_ID is char(6) with no default and three tables carry a
 *     foreign key into it, so it is generated in the existing six-uppercase shape
 *     and is NOT editable through the form.
 *
 *  3. Deletion. listing, insight and trend all reference crop_category with no
 *     ON DELETE CASCADE, so a category anything still points at has to be refused
 *     with an explanation instead of surfacing a raw foreign key error. This is the
 *     case a listings-only guard would miss.
 *
 * Runs against MySQL: the constraints being defended are MySQL foreign keys, and
 * sqlite would not enforce them the same way (see phpunit.mysql.xml).
 */
class CropCategoryAdminTest extends TestCase
{
    use RefreshDatabase;

    private function id(string $table): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where('CAT_ID', $id)->exists());

        return $id;
    }

    private function makeUser(string $role = 'GENERAL_USER'): User
    {
        $id = strtoupper(Str::random(6));

        return User::create([
            'USR_ID' => $id,
            'USR_NAME' => $role === 'ADMIN' ? 'Admin Person' : 'Ordinary Person',
            'USR_EMAIL' => strtolower($id).'@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '09'.$id,
            'USR_ROLE' => $role,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
    }

    private function makeCategory(string $name = 'Leafy Vegetables', array $overrides = []): CropCategory
    {
        return CropCategory::create(array_merge([
            'CAT_ID' => $this->id('crop_category'),
            'CAT_NAME' => $name,
            'CAT_ICON' => 'spa',
            'CAT_DESCRIPTION' => 'Leaf and stem crops.',
        ], $overrides));
    }

    /**
     * A listing in a category, which is the reference that has to block a delete.
     *
     * listing.CAT_ID is NOT NULL with a real foreign key, so the whole chain has to
     * exist — farm and farmer and buyer — before a row can be written.
     */
    private function makeListingIn(string $categoryId): Listing
    {
        $buyer = Buyer::create([
            'BUY_ID' => strtoupper(Str::random(6)),
            'USR_ID' => $this->makeUser()->USR_ID,
        ]);

        $farmer = Farmer::create([
            'FMR_ID' => strtoupper(Str::random(6)),
            'BUY_ID' => $buyer->BUY_ID,
        ]);

        $farm = Farm::create([
            'FRM_ID' => strtoupper(Str::random(6)),
            'FRM_NAME' => 'Panel Test Farm',
            'FRM_BARANGAY' => 'Sudlon II',
            'FRM_LATITUDE' => 10.30,
            'FRM_LONGITUDE' => 123.89,
            'FRM_CREATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
        ]);

        return Listing::create([
            'LST_ID' => strtoupper(Str::random(6)),
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $farmer->FMR_ID,
            'FRM_ID' => $farm->FRM_ID,
            'CAT_ID' => $categoryId,
        ]);
    }

    private function makeInsightIn(string $categoryId): void
    {
        Insight::create([
            'INS_ID' => strtoupper(Str::random(6)),
            'INS_TITLE' => 'Buyer interest',
            'INS_CONTENT' => 'Leafy crops came up repeatedly in search.',
            'INS_CREATED_AT' => now(),
            'CAT_ID' => $categoryId,
        ]);
    }

    private function makeTrendIn(string $categoryId): void
    {
        Trend::create([
            'TRND_ID' => strtoupper(Str::random(6)),
            'TRND_TITLE' => 'Leafy demand',
            'TRND_DATA' => '{"count":12}',
            'TRND_CREATED_AT' => now(),
            'TRND_PERIOD_MONTH' => now()->format('Y-m'),
            'CAT_ID' => $categoryId,
        ]);
    }

    public function test_the_panel_is_reachable_from_the_listings_page(): void
    {
        $category = $this->makeCategory('Root Crops');

        $response = $this->actingAs($this->makeUser('ADMIN'))->get('/listings');

        $response->assertOk();
        // The panel is embedded, not linked to a page of its own.
        $response->assertSee('Manage Categories');
        $response->assertSee('id="categoryPanel"', false);
        $response->assertSee('Root Crops');
        // The id is shown to the admin but never submitted.
        $response->assertSee($category->CAT_ID);
        $response->assertDontSee('name="CAT_ID"', false);
    }

    public function test_the_delete_control_is_a_real_form_with_a_method_override(): void
    {
        // Not a JS-built request. The panel has to delete with the script blocked,
        // and the request still has to carry CSRF and the DELETE override like
        // every other destructive action in the panel.
        $category = $this->makeCategory('Spare Category');

        $response = $this->actingAs($this->makeUser('ADMIN'))->get('/listings');

        $response->assertSee('action="'.route('categories.destroy', $category->CAT_ID).'"', false);
        $response->assertSee('name="_method"', false);
        $response->assertSee('value="DELETE"', false);
    }

    public function test_the_delete_form_carries_the_current_listings_filters(): void
    {
        // Same reason the controller carries them back on redirect: a category edit
        // that also threw away the moderator's search box would be its own bug.
        $this->makeCategory('Spare Category');

        $response = $this->actingAs($this->makeUser('ADMIN'))
            ->get('/listings?search=tomato&status=ACTIVE');

        $response->assertSee('name="search"', false);
        $response->assertSee('value="tomato"', false);
        $response->assertSee('name="status"', false);
        $response->assertSee('value="ACTIVE"', false);
    }

    public function test_a_category_in_use_renders_a_disabled_delete_button(): void
    {
        // The server refuses this delete anyway. Greying it out is what stops the
        // moderator spending a click to be told no.
        $category = $this->makeCategory('Root Crops');
        $this->makeListingIn($category->CAT_ID);

        $response = $this->actingAs($this->makeUser('ADMIN'))->get('/listings');

        // Asserted in two halves rather than as one sentence: the em dash is the
        // character itself in the rendered title, not an &mdash; entity, because
        // Blade escapes the string but does not entity-encode Unicode. Matching the
        // whole sentence with either form would have encoded that detail into the
        // assertion and made it read as if the HTML contained an entity.
        $response->assertSee('Used by 1 row(s)', false);
        $response->assertSee('move or remove them first', false);
        $response->assertSee('disabled', false);
    }

    public function test_a_general_user_cannot_reach_the_panel(): void
    {
        $this->actingAs($this->makeUser())
            ->get('/listings')
            ->assertForbidden();
    }

    public function test_an_admin_creates_a_category(): void
    {
        $response = $this->actingAs($this->makeUser('ADMIN'))
            ->post('/categories', [
                'CAT_NAME' => 'Leafy Vegetables',
                'CAT_ICON' => 'spa',
                'CAT_DESCRIPTION' => 'Crops harvested for their leaves.',
            ]);

        $response->assertRedirect('/listings');
        $response->assertSessionHas('success');

        $category = CropCategory::where('CAT_NAME', 'Leafy Vegetables')->first();

        $this->assertNotNull($category, 'the category should exist after create');
        // Same six-uppercase shape as the ids already in the table.
        $this->assertMatchesRegularExpression('/^[A-Z0-9]{6}$/', $category->CAT_ID);
        $this->assertSame('spa', $category->CAT_ICON);
        $this->assertSame('Crops harvested for their leaves.', $category->CAT_DESCRIPTION);
    }

    public function test_a_general_user_cannot_create_a_category_by_posting_directly(): void
    {
        $this->actingAs($this->makeUser())
            ->post('/categories', ['CAT_NAME' => 'Smuggled Category'])
            ->assertForbidden();

        $this->assertSame(0, CropCategory::where('CAT_NAME', 'Smuggled Category')->count());
    }

    public function test_a_guest_cannot_create_a_category(): void
    {
        $this->post('/categories', ['CAT_NAME' => 'Anonymous Category'])
            ->assertRedirect('/login');

        $this->assertSame(0, CropCategory::where('CAT_NAME', 'Anonymous Category')->count());
    }

    public function test_a_duplicate_name_is_refused_with_a_readable_message(): void
    {
        $this->makeCategory('Root Crops');

        $response = $this->actingAs($this->makeUser('ADMIN'))
            ->from('/listings')
            ->post('/categories', ['CAT_NAME' => 'Root Crops']);

        $response->assertRedirect('/listings');
        $response->assertSessionHasErrors('CAT_NAME');
        // Not a raw SQLSTATE 1062 from the unique key.
        $this->assertSame(1, CropCategory::where('CAT_NAME', 'Root Crops')->count());
    }

    public function test_a_name_is_required(): void
    {
        $response = $this->actingAs($this->makeUser('ADMIN'))
            ->from('/listings')
            ->post('/categories', ['CAT_ICON' => 'spa']);

        $response->assertSessionHasErrors('CAT_NAME');
        $this->assertSame(0, CropCategory::count());
    }

    public function test_an_icon_must_be_an_icon_name(): void
    {
        $this->actingAs($this->makeUser('ADMIN'))
            ->from('/listings')
            ->post('/categories', [
                'CAT_NAME' => 'Bad Icon Category',
                'CAT_ICON' => '<script>alert(1)</script>',
            ])
            ->assertSessionHasErrors('CAT_ICON');

        $this->assertSame(0, CropCategory::where('CAT_NAME', 'Bad Icon Category')->count());
    }

    public function test_a_well_formed_but_unknown_icon_is_refused(): void
    {
        // The case that made the free-text field a problem. 'spaa' is a clean token
        // and would have passed the old regex, but the app does not know it, so it
        // fell through to guessing from the category name. A moderator would have
        // seen a generic leaf and no explanation. The picker prevents the typo and
        // this rule stops the value getting in any other way.
        $this->actingAs($this->makeUser('ADMIN'))
            ->from('/listings')
            ->post('/categories', [
                'CAT_NAME' => 'Mystery Category',
                'CAT_ICON' => 'spaa',
            ])
            ->assertSessionHasErrors('CAT_ICON');

        $this->assertSame(0, CropCategory::where('CAT_NAME', 'Mystery Category')->count());
    }

    public function test_the_icon_is_optional(): void
    {
        $this->actingAs($this->makeUser('ADMIN'))
            ->post('/categories', [
                'CAT_NAME' => 'Uncategorised Goods',
                'CAT_ICON' => null,
            ])
            ->assertSessionHasNoErrors();

        $category = CropCategory::where('CAT_NAME', 'Uncategorised Goods')->firstOrFail();
        $this->assertNull($category->CAT_ICON);
    }

    public function test_every_icon_the_picker_offers_is_accepted(): void
    {
        // The picker and the validator are driven by the same constant, so this is
        // the test that stops them drifting apart from each other, and the one that
        // would catch an ICONS entry the app cannot actually render.
        foreach (array_keys(CropCategory::ICONS) as $index => $iconName) {
            $this->actingAs($this->makeUser('ADMIN'))
                ->post('/categories', [
                    'CAT_NAME' => 'Picker Category '.$index,
                    'CAT_ICON' => $iconName,
                ])
                ->assertSessionHasNoErrors();
        }

        $this->assertSame(count(CropCategory::ICONS), CropCategory::count());
    }

    public function test_the_picker_offers_a_picture_for_every_icon_the_app_can_draw(): void
    {
        // The eight names are the contract with the Flutter app: add_crop_screen's
        // _iconForCategory switch maps exactly these, and nothing else. Asserted
        // here as a set so adding an icon on one side and forgetting the other is a
        // failing test rather than a category that quietly renders a generic leaf.
        $offered = array_keys(CropCategory::ICONS);
        sort($offered);

        // Sorted before comparing because the order the picker lays the icons out
        // in is a presentation choice. Asserting the order would be asserting a
        // layout detail and would fail on a reordering that changed nothing.
        $this->assertSame([
            'agriculture',
            'eco',
            'grain',
            'grass',
            'local_florist',
            'pets',
            'spa',
            'water_drop',
        ], $offered);
    }

    public function test_the_panel_draws_the_picker_instead_of_asking_for_an_icon_name(): void
    {
        $response = $this->actingAs($this->makeUser('ADMIN'))->get('/listings');

        $response->assertSee('id="categoryIconGrid"', false);

        foreach (array_keys(CropCategory::ICONS) as $iconName) {
            $response->assertSee('data-icon="'.$iconName.'"', false);
        }

        // The name is submitted through a hidden field the grid writes, so nobody
        // is asked to spell one.
        //
        // Checked by counting the fields named CAT_ICON and confirming the only one
        // is hidden, rather than by pattern-matching the rendered markup for the
        // absence of a text input. The old version of this assertion searched for a
        // specific run of whitespace inside the Blade template, which would have
        // failed the moment the file was reindented while the form kept working
        // exactly as intended.
        $fields = $response->getContent();
        $this->assertSame(
            1,
            preg_match_all('/<input\b[^>]*\bname="CAT_ICON"/', $fields),
            'expected exactly one CAT_ICON field, so the icon cannot be typed twice over'
        );

        // Read the whole tag before judging it, rather than demanding name come
        // before type: attribute order in a template is not a contract, and an
        // assertion that depended on it would fail on a harmless reorder.
        preg_match('/<input\b[^>]*\bname="CAT_ICON"[^>]*>/', $fields, $tag);
        $this->assertStringContainsString(
            'type="hidden"',
            $tag[0],
            'the icon must not be an editable text field'
        );
    }

    public function test_the_picker_offers_no_icon_as_a_choice(): void
    {
        // Iconless is a real state, not an oversight: a category can legitimately
        // have none, so the grid needs a way back to that from a set value.
        $response = $this->actingAs($this->makeUser('ADMIN'))->get('/listings');

        $response->assertSee('data-icon=""', false);
    }

    public function test_an_admin_updates_a_category_without_changing_its_id(): void
    {
        $category = $this->makeCategory('Root Crops');
        $originalId = $category->CAT_ID;

        $response = $this->actingAs($this->makeUser('ADMIN'))
            ->put('/categories/'.$originalId, [
                'CAT_NAME' => 'Root & Tuber Crops',
                'CAT_ICON' => 'agriculture',
                'CAT_DESCRIPTION' => 'Carrot, radish, sweet potato, cassava, ube.',
            ]);

        $response->assertRedirect('/listings');
        $response->assertSessionHas('success');

        $category->refresh();

        $this->assertSame('Root & Tuber Crops', $category->CAT_NAME);
        $this->assertSame('agriculture', $category->CAT_ICON);
        // The id is not in the payload and must not move: listings, insights and
        // trends all point at it, and the app keys its cached categories off it.
        $this->assertSame($originalId, $category->CAT_ID);
    }

    public function test_a_category_keeps_its_id_when_it_is_renamed(): void
    {
        $category = $this->makeCategory('Root Crops');
        $originalId = $category->CAT_ID;
        $listing = $this->makeListingIn($originalId);

        $this->actingAs($this->makeUser('ADMIN'))
            ->put('/categories/'.$originalId, ['CAT_NAME' => 'Root Crops Revised'])
            ->assertRedirect('/listings');

        $this->assertDatabaseHas('crop_category', [
            'CAT_ID' => $originalId,
            'CAT_NAME' => 'Root Crops Revised',
        ]);

        // The listing still resolves to its category, which is what would break if
        // the id were editable.
        $this->assertSame('Root Crops Revised', $listing->fresh()->category->CAT_NAME);
    }

    public function test_updating_without_changing_the_name_is_allowed(): void
    {
        // Every save rewrites the whole form, so the unique rule must ignore the
        // row being edited. Without that, saving an edit would fail on the
        // category's own unchanged name.
        $category = $this->makeCategory('Root Crops');

        $this->actingAs($this->makeUser('ADMIN'))
            ->put('/categories/'.$category->CAT_ID, [
                'CAT_NAME' => 'Root Crops',
                'CAT_ICON' => 'agriculture',
            ])
            ->assertSessionHasNoErrors();

        $this->assertSame('agriculture', $category->fresh()->CAT_ICON);
    }

    public function test_a_duplicate_name_is_refused_on_update_too(): void
    {
        $this->makeCategory('Root Crops');
        $other = $this->makeCategory('Herbs & Spices');

        $this->actingAs($this->makeUser('ADMIN'))
            ->from('/listings')
            ->put('/categories/'.$other->CAT_ID, ['CAT_NAME' => 'Root Crops'])
            ->assertSessionHasErrors('CAT_NAME');

        $this->assertSame('Herbs & Spices', $other->fresh()->CAT_NAME);
    }

    public function test_a_general_user_cannot_update_or_delete_a_category(): void
    {
        $category = $this->makeCategory('Root Crops');
        $user = $this->makeUser();

        $this->actingAs($user)
            ->put('/categories/'.$category->CAT_ID, ['CAT_NAME' => 'Hijacked'])
            ->assertForbidden();

        $this->actingAs($user)
            ->delete('/categories/'.$category->CAT_ID)
            ->assertForbidden();

        $this->assertDatabaseHas('crop_category', [
            'CAT_ID' => $category->CAT_ID,
            'CAT_NAME' => 'Root Crops',
        ]);
    }

    public function test_an_unused_category_can_be_deleted(): void
    {
        $category = $this->makeCategory('Spare Category');

        $response = $this->actingAs($this->makeUser('ADMIN'))
            ->delete('/categories/'.$category->CAT_ID);

        $response->assertRedirect('/listings');
        $response->assertSessionHas('success');

        $this->assertDatabaseMissing('crop_category', ['CAT_ID' => $category->CAT_ID]);
    }

    public function test_a_category_with_a_listing_cannot_be_deleted(): void
    {
        // The real failure this prevents: listing.CAT_ID is NOT NULL with a foreign
        // key and no ON DELETE CASCADE, so without the guard the delete is a
        // SQLSTATE 23000 rather than a sentence a moderator can act on.
        $category = $this->makeCategory('Root Crops');
        $this->makeListingIn($category->CAT_ID);

        $response = $this->actingAs($this->makeUser('ADMIN'))
            ->delete('/categories/'.$category->CAT_ID);

        $response->assertRedirect('/listings');
        $response->assertSessionHas('error');
        $response->assertSessionMissing('success');

        $this->assertDatabaseHas('crop_category', ['CAT_ID' => $category->CAT_ID]);
    }

    public function test_the_refusal_says_how_many_listings_block_the_delete(): void
    {
        $category = $this->makeCategory('Root Crops');
        $this->makeListingIn($category->CAT_ID);
        $this->makeListingIn($category->CAT_ID);

        $this->actingAs($this->makeUser('ADMIN'))
            ->delete('/categories/'.$category->CAT_ID)
            ->assertSessionHas('error', fn ($message) => str_contains($message, '2 listings'));
    }

    public function test_a_category_with_only_analytics_rows_cannot_be_deleted(): void
    {
        // No listings at all, so a listings-only guard would show the button as
        // enabled and the delete would still be refused by the database.
        $category = $this->makeCategory('Root Crops');
        $this->makeInsightIn($category->CAT_ID);

        $response = $this->actingAs($this->makeUser('ADMIN'))
            ->delete('/categories/'.$category->CAT_ID);

        $response->assertSessionHas('error');
        $this->assertDatabaseHas('crop_category', ['CAT_ID' => $category->CAT_ID]);
    }

    public function test_a_category_with_only_trend_rows_cannot_be_deleted(): void
    {
        $category = $this->makeCategory('Root Crops');
        $this->makeTrendIn($category->CAT_ID);

        $this->actingAs($this->makeUser('ADMIN'))
            ->delete('/categories/'.$category->CAT_ID)
            ->assertSessionHas('error');

        $this->assertDatabaseHas('crop_category', ['CAT_ID' => $category->CAT_ID]);
    }

    public function test_the_refusal_names_the_analytics_rows_rather_than_saying_rows(): void
    {
        // "12 rows" with no noun reads as a bug. The moderator can act on listings;
        // they cannot act on trends, so the message says which is which.
        $category = $this->makeCategory('Root Crops');
        $this->makeTrendIn($category->CAT_ID);
        $this->makeTrendIn($category->CAT_ID);

        $this->actingAs($this->makeUser('ADMIN'))
            ->delete('/categories/'.$category->CAT_ID)
            ->assertSessionHas('error', fn ($message) => str_contains($message, '2 trend rows'));
    }

    public function test_usage_counts_cover_all_three_referencing_tables(): void
    {
        $category = $this->makeCategory('Root Crops');
        $this->makeListingIn($category->CAT_ID);
        $this->makeInsightIn($category->CAT_ID);
        $this->makeTrendIn($category->CAT_ID);

        $this->assertSame([
            'listings' => 1,
            'insights' => 1,
            'trends' => 1,
        ], $category->usageCounts());
    }

    public function test_the_listings_filter_survives_a_category_change(): void
    {
        // The panel is embedded in the Listings page, so returning to a bare
        // /listings would also throw away the search box and status filter the
        // moderator had set up.
        $category = $this->makeCategory('Root Crops');

        $this->actingAs($this->makeUser('ADMIN'))
            ->post('/categories?search=tomato&status=ACTIVE&page=2', [
                'CAT_NAME' => 'New Category',
            ])
            ->assertRedirect('/listings?search=tomato&status=ACTIVE&page=2');
    }

    public function test_a_missing_category_on_update_is_a_404(): void
    {
        $this->actingAs($this->makeUser('ADMIN'))
            ->put('/categories/NOPE99', ['CAT_NAME' => 'Whatever'])
            ->assertNotFound();
    }

    public function test_a_missing_category_on_delete_is_a_404(): void
    {
        $this->actingAs($this->makeUser('ADMIN'))
            ->delete('/categories/NOPE99')
            ->assertNotFound();
    }
}