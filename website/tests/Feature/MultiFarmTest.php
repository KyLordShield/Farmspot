<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\Conversation;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\FarmPhoto;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * One account, many farms.
 *
 * The schema always allowed this (farm.FMR_ID is not unique) — what used to stop
 * a second farm was a single guard in the controller. These tests pin the
 * behaviour that replaced it:
 *
 *  1. The first farm still has to be verified: ID and permit are required.
 *  2. Later farms inherit those same documents instead of demanding them again,
 *     because the person and their permit did not change.
 *  3. A new document is still honoured, so a seller can replace a bad one.
 *  4. Every farm is a real, separately reviewed row — status, location and
 *     documents are per farm, never shared or overwritten.
 */
class MultiFarmTest extends TestCase
{
    use RefreshDatabase;

    private const ENDPOINT = '/api/farms';

    private User $user;

    private string $buyerId;

    private string $farmerId;

    protected function setUp(): void
    {
        parent::setUp();

        // The farm endpoints write uploads to Cloudinary; a fake disk keeps the
        // test hermetic and stops it reaching the network.
        Storage::fake('cloudinary');

        $this->user = User::create([
            'USR_ID' => strtoupper(Str::random(6)),
            'USR_NAME' => 'Multi Farm Seller',
            'USR_EMAIL' => 'multifarm@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0917' . str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);

        // The user -> buyer -> farmer chain that "Become a Seller" normally
        // creates. Only a seller with a farmer row may submit a farm.
        $this->buyerId = strtoupper(Str::random(6));
        Buyer::create(['BUY_ID' => $this->buyerId, 'USR_ID' => $this->user->USR_ID]);

        $this->farmerId = strtoupper(Str::random(6));
        Farmer::create([
            'FMR_ID' => $this->farmerId,
            'BUY_ID' => $this->buyerId,
            'FMR_SELLER_MODE_ACTIVE' => 1,
        ]);
    }

    /** A complete first-farm submission, documents included. */
    private function firstFarmPayload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'First Farm',
            'barangay' => 'Bayan',
            'latitude' => 10.1,
            'longitude' => 121.1,
            'photos' => [UploadedFile::fake()->create('upload.jpg', 10, 'image/jpeg')],
            'verification_document' => UploadedFile::fake()->create('id.jpg', 10, 'image/jpeg'),
            'farm_certificate' => UploadedFile::fake()->create('permit.pdf', 40, 'application/pdf'),
        ], $overrides);
    }

    private function postFarm(array $payload)
    {
        // Multipart upload, but still ask for JSON back: without the Accept
        // header Laravel redirects on a validation failure instead of returning
        // the 422 body, which would make the assertions test the wrong thing.
        return $this->actingAs($this->user, 'sanctum')
            ->withHeaders(['Accept' => 'application/json'])
            ->post(self::ENDPOINT, $payload);
    }

    /**
     * Looks a farm up by name rather than by creation order: two submissions in
     * one test can share the same FRM_CREATED_AT second, which would make an
     * ordered query non-deterministic for reasons that have nothing to do with
     * the behaviour under test.
     */
    private function farmNamed(string $name): Farm
    {
        return Farm::where('FRM_NAME', $name)->firstOrFail();
    }

    public function test_a_seller_who_is_not_a_farmer_cannot_submit_a_farm(): void
    {
        $user = User::create([
            'USR_ID' => strtoupper(Str::random(6)),
            'USR_NAME' => 'Buyer Only',
            'USR_EMAIL' => 'buyeronly@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0918' . str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);

        $this->actingAs($user, 'sanctum')
            ->post(self::ENDPOINT, $this->firstFarmPayload())
            ->assertForbidden();
    }

    public function test_the_first_farm_still_requires_both_documents(): void
    {
        // Guard against the inheritance rule being applied too eagerly and
        // letting a brand-new seller through with nothing on file.
        $this->postFarm($this->firstFarmPayload(['verification_document' => null]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('verification_document');

        $this->postFarm($this->firstFarmPayload(['farm_certificate' => null]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('farm_certificate');

        $this->assertSame(0, Farm::count());
    }

    public function test_a_second_farm_does_not_need_the_documents_again(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();

        $response = $this->postFarm([
            'name' => 'Second Farm',
            'barangay' => 'Barangay Dos',
            'latitude' => 10.2,
            'longitude' => 121.2,
            'photos' => [UploadedFile::fake()->create('upload.jpg', 10, 'image/jpeg')],
            // No documents: this is the whole point of the change.
        ]);

        $response->assertCreated()
            ->assertJsonPath('documents_required', false)
            ->assertJsonPath('documents_inherited', true);

        $this->assertSame(2, Farm::count());
    }

    public function test_a_second_farm_inherits_the_first_farms_documents(): void
    {
        $first = $this->postFarm($this->firstFarmPayload())->assertCreated();
        $firstId = $first->json('farm_id');

        $secondId = $this->postFarm([
            'name' => 'Second Farm',
            'barangay' => 'Barangay Dos',
            'latitude' => 10.2,
            'longitude' => 121.2,
            'photos' => [UploadedFile::fake()->create('upload.jpg', 10, 'image/jpeg')],
        ])->json('farm_id');

        $original = $this->farmNamed('First Farm');
        $copy = $this->farmNamed('Second Farm');

        // Each farm still carries its own document values; the second simply
        // points at the same files, so the columns stay meaningful.
        $this->assertNotNull($original->FRM_VERIFICATION_DOC_PATH);
        $this->assertNotNull($original->FRM_FARM_CERTIFICATE_PATH);
        $this->assertSame($original->FRM_VERIFICATION_DOC_PATH, $copy->FRM_VERIFICATION_DOC_PATH);
        $this->assertSame($original->FRM_FARM_CERTIFICATE_PATH, $copy->FRM_FARM_CERTIFICATE_PATH);
    }

    public function test_a_second_farm_may_replace_inherited_documents(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();

        $secondId = $this->postFarm([
            'name' => 'Second Farm',
            'barangay' => 'Barangay Dos',
            'latitude' => 10.2,
            'longitude' => 121.2,
            'photos' => [UploadedFile::fake()->create('upload.jpg', 10, 'image/jpeg')],
            'verification_document' => UploadedFile::fake()->create('new-id.jpg', 10, 'image/jpeg'),
        ])->assertCreated()->json('farm_id');

        $first = $this->farmNamed('First Farm');
        $second = $this->farmNamed('Second Farm');

        $this->assertNotSame(
            $first->FRM_VERIFICATION_DOC_PATH,
            $second->FRM_VERIFICATION_DOC_PATH,
            'a fresh upload should win over the inherited file'
        );
        // The untouched document still falls back to the first farm's copy.
        $this->assertSame(
            $first->FRM_FARM_CERTIFICATE_PATH,
            $second->FRM_FARM_CERTIFICATE_PATH
        );
    }

    public function test_each_farm_is_its_own_row_with_its_own_status(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $this->postFarm([
            'name' => 'Second Farm',
            'barangay' => 'Barangay Dos',
            'latitude' => 10.2,
            'longitude' => 121.2,
            'photos' => [UploadedFile::fake()->create('upload.jpg', 10, 'image/jpeg')],
        ])->assertCreated();

        $farms = Farm::all()->keyBy('FRM_NAME');

        $this->assertCount(2, $farms);
        $this->assertSame('Bayan', $farms['First Farm']->FRM_BARANGAY);
        $this->assertSame('Barangay Dos', $farms['Second Farm']->FRM_BARANGAY);
        $this->assertNotSame(
            $farms['First Farm']->FRM_ID,
            $farms['Second Farm']->FRM_ID
        );

        // Neither farm is approved or pinned until review, and approving one
        // must never silently approve the other.
        foreach ($farms as $farm) {
            $this->assertSame('PENDING_REVIEW', $farm->FRM_STATUS);
            $this->assertSame(0, $farm->FRM_PIN_ACTIVE);
        }
    }

    public function test_the_sellers_farm_list_returns_every_farm(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $this->postFarm([
            'name' => 'Second Farm',
            'barangay' => 'Barangay Dos',
            'latitude' => 10.2,
            'longitude' => 121.2,
            'photos' => [UploadedFile::fake()->create('upload.jpg', 10, 'image/jpeg')],
        ])->assertCreated();

        // This is what the app's farm switcher is built on: it must be a list
        // of everything the seller owns, not a single "the farm".
        $response = $this->actingAs($this->user, 'sanctum')
            ->getJson(self::ENDPOINT)
            ->assertOk();

        $names = array_column($response->json('farms'), 'FRM_NAME');
        sort($names);

        $this->assertSame(['First Farm', 'Second Farm'], $names);
    }

    public function test_stats_stay_scoped_to_one_farm(): void
    {
        $firstId = $this->postFarm($this->firstFarmPayload())->json('farm_id');
        $secondId = $this->postFarm([
            'name' => 'Second Farm',
            'barangay' => 'Barangay Dos',
            'latitude' => 10.2,
            'longitude' => 121.2,
            'photos' => [UploadedFile::fake()->create('upload.jpg', 10, 'image/jpeg')],
        ])->json('farm_id');

        // A visit on one farm must not show up in the other's numbers.
        $this->actingAs($this->user, 'sanctum')
            ->postJson("/api/farms/{$secondId}/log-visit")
            ->assertCreated();

        $first = $this->actingAs($this->user, 'sanctum')
            ->getJson("/api/farms/{$firstId}/stats")
            ->assertOk();
        $second = $this->actingAs($this->user, 'sanctum')
            ->getJson("/api/farms/{$secondId}/stats")
            ->assertOk();

        $this->assertSame(0, $first->json('profile_views'));
        $this->assertSame(1, $second->json('profile_views'));
    }

    /*
    |--------------------------------------------------------------------------
    | Removing a farm
    |--------------------------------------------------------------------------
    |
    | "Remove" is an archive, not a delete. The reason is the schema: 
    | conversation.FRM_ID, contact_log and farm_visit_log are all ON DELETE
    | CASCADE from farm, so a real delete would silently destroy the seller's
    | buyer message history. Archiving keeps every row and only hides the farm.
    |
    */

    /** A second farm, added the way the app adds one. */
    private function addSecondFarm(): string
    {
        return $this->postFarm([
            'name' => 'Second Farm',
            'barangay' => 'Barangay Dos',
            'latitude' => 10.2,
            'longitude' => 121.2,
            'photos' => [UploadedFile::fake()->create('upload.jpg', 10, 'image/jpeg')],
        ])->json('farm_id');
    }

    private function deleteFarm(string $farmId)
    {
        return $this->actingAs($this->user, 'sanctum')
            ->deleteJson("/api/farms/{$farmId}");
    }

    public function test_a_seller_cannot_remove_their_only_farm(): void
    {
        $onlyFarmId = $this->postFarm($this->firstFarmPayload())->json('farm_id');

        // The last farm is the account's whole reason for selling, so it stays.
        // Going inactive is done by deactivating the seller, not by deleting.
        $response = $this->deleteFarm($onlyFarmId)
            ->assertStatus(422)
            ->assertJson(['code' => 'LAST_FARM']);

        $this->assertStringContainsString(
            'only farm',
            $response->json('message')
        );

        $farm = $this->farmNamed('First Farm');
        $this->assertSame('PENDING_REVIEW', $farm->FRM_STATUS);
    }

    public function test_a_seller_can_remove_one_of_several_farms(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $secondId = $this->addSecondFarm();

        $this->deleteFarm($secondId)
            ->assertOk()
            ->assertJson(['farm_id' => $secondId, 'remaining_farms' => 1]);

        $farm = $this->farmNamed('Second Farm');
        $this->assertSame('ARCHIVED', $farm->FRM_STATUS);
        $this->assertSame(0, $farm->FRM_PIN_ACTIVE);
    }

    public function test_an_archived_farm_row_and_its_photos_are_kept(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $secondId = $this->addSecondFarm();

        $photoCountBefore = FarmPhoto::where('FRM_ID', $secondId)->count();
        $this->assertGreaterThan(0, $photoCountBefore);

        $this->deleteFarm($secondId)->assertOk();

        // Archiving hides the farm, it does not erase it: the row survives so
        // the history attached to it stays readable and the farm is restorable.
        $this->assertDatabaseHas('farm', [
            'FRM_ID' => $secondId,
            'FRM_STATUS' => 'ARCHIVED',
        ]);
        $this->assertSame(
            $photoCountBefore,
            FarmPhoto::where('FRM_ID', $secondId)->count()
        );
    }

    public function test_an_archived_farm_disappears_from_the_switcher_but_not_the_map_query(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $secondId = $this->addSecondFarm();

        $this->deleteFarm($secondId)->assertOk();

        $names = array_column(
            $this->actingAs($this->user, 'sanctum')
                ->getJson(self::ENDPOINT)
                ->assertOk()
                ->json('farms'),
            'FRM_NAME'
        );

        // The switcher only offers APPROVED / PENDING_REVIEW farms, so the
        // archived one is gone from it without any extra filtering.
        $this->assertSame(['First Farm'], $names);
    }

    public function test_buyers_can_no_longer_find_an_archived_farm_on_the_map(): void
    {
        $firstId = $this->postFarm($this->firstFarmPayload())->json('farm_id');
        $secondId = $this->addSecondFarm();

        // Approve and pin both, the state they would be in once reviewed.
        foreach ([$firstId, $secondId] as $farmId) {
            $farm = Farm::find($farmId);
            $farm->FRM_STATUS = 'APPROVED';
            $farm->FRM_PIN_ACTIVE = 1;
            $farm->save();
        }

        $this->actingAs($this->user, 'sanctum')
            ->deleteJson("/api/farms/{$secondId}")
            ->assertOk();

        $pinnedIds = array_column(
            $this->getJson('/api/farms/public')->assertOk()->json('farms'),
            'id'
        );

        $this->assertContains($firstId, $pinnedIds);
        $this->assertNotContains($secondId, $pinnedIds);
    }

    public function test_removing_a_farm_stops_its_crops_being_offered(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $secondId = $this->addSecondFarm();

        $category = CropCategory::firstOrCreate(
            ['CAT_NAME' => 'Rice Archive Test'],
            ['CAT_ID' => strtoupper(Str::random(6))]
        );

        $listingId = strtoupper(Str::random(6));
        Listing::create([
            'LST_ID' => $listingId,
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $this->farmerId,
            'FRM_ID' => $secondId,
            'CAT_ID' => $category->CAT_ID,
        ]);

        $this->deleteFarm($secondId)->assertOk();

        // Withdrawn, not destroyed: the listing row is still there to be
        // reactivated if the farm is ever restored. REMOVED is the same state
        // the seller's own delete-listing action uses.
        $this->assertDatabaseHas('listing', [
            'LST_ID' => $listingId,
            'LST_AVAILABILITY' => 'REMOVED',
        ]);
    }

    public function test_removing_a_farm_keeps_the_buyer_conversations_about_it(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $secondId = $this->addSecondFarm();

        $category = CropCategory::firstOrCreate(
            ['CAT_NAME' => 'Rice Archive Chat Test'],
            ['CAT_ID' => strtoupper(Str::random(6))]
        );

        $listingId = strtoupper(Str::random(6));
        Listing::create([
            'LST_ID' => $listingId,
            'LST_STATUS' => 'AVAILABLE_NOW',
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $this->farmerId,
            'FRM_ID' => $secondId,
            'CAT_ID' => $category->CAT_ID,
        ]);

        // A buyer who already opened a thread with this farm.
        $buyerUser = User::create([
            'USR_ID' => strtoupper(Str::random(6)),
            'USR_NAME' => 'Archive Buyer',
            'USR_EMAIL' => 'archivebuyer@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0919' . str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
        $archiveBuyerId = strtoupper(Str::random(6));
        Buyer::create(['BUY_ID' => $archiveBuyerId, 'USR_ID' => $buyerUser->USR_ID]);

        $conversationId = strtoupper(Str::random(6));
        Conversation::create([
            'CONV_ID' => $conversationId,
            'LST_ID' => $listingId,
            'FRM_ID' => $secondId,
            'BUY_ID' => $archiveBuyerId,
            'FMR_ID' => $this->farmerId,
            'CONV_CREATED_AT' => now(),
        ]);

        $this->deleteFarm($secondId)->assertOk();

        // This is the whole reason removal is an archive: with a hard DELETE
        // the conversation.FRM_ID cascade would have taken this row with it.
        $this->assertDatabaseHas('conversation', [
            'CONV_ID' => $conversationId,
            'FRM_ID' => $secondId,
        ]);
    }

    public function test_a_seller_cannot_remove_someone_elses_farm(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $secondId = $this->addSecondFarm();

        $intruder = User::create([
            'USR_ID' => strtoupper(Str::random(6)),
            'USR_NAME' => 'Nosy Seller',
            'USR_EMAIL' => 'nosy@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0920' . str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
        $nosyBuyerId = strtoupper(Str::random(6));
        Buyer::create(['BUY_ID' => $nosyBuyerId, 'USR_ID' => $intruder->USR_ID]);
        $nosyFarmerId = strtoupper(Str::random(6));
        Farmer::create([
            'FMR_ID' => $nosyFarmerId,
            'BUY_ID' => $nosyBuyerId,
            'FMR_SELLER_MODE_ACTIVE' => 1,
        ]);

        $this->actingAs($intruder, 'sanctum')
            ->deleteJson("/api/farms/{$secondId}")
            ->assertForbidden();

        $this->assertSame('PENDING_REVIEW', $this->farmNamed('Second Farm')->FRM_STATUS);
    }

    public function test_a_seller_cannot_remove_a_farm_that_does_not_exist(): void
    {
        $this->postFarm($this->firstFarmPayload())->assertCreated();
        $this->addSecondFarm();

        $this->deleteFarm('ZZZZZZ')->assertNotFound();
    }

    public function test_an_archived_farm_does_not_count_towards_the_last_farm_check(): void
    {
        $firstId = $this->postFarm($this->firstFarmPayload())->json('farm_id');
        $secondId = $this->addSecondFarm();

        $this->deleteFarm($secondId)->assertOk();

        // One farm left and it is the archived one plus the original: the
        // seller is back to a single farm, so the guard must bite again.
        $this->deleteFarm($firstId)
            ->assertStatus(422)
            ->assertJson(['code' => 'LAST_FARM']);

        $this->assertSame('PENDING_REVIEW', $this->farmNamed('First Farm')->FRM_STATUS);
    }
}
