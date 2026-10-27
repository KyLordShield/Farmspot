<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class ListingDuplicateNameTest extends TestCase
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
        ][$prefix];

        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($table)->where("{$prefix}_ID", $id)->exists());

        return $id;
    }

    private function makeSeller(): array
    {
        $user = User::create([
            'USR_ID' => $this->id('USR'),
            'USR_NAME' => 'Reyes',
            'USR_EMAIL' => 'renew'.Str::lower(Str::random(6)).'@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '0917'.str_pad((string) random_int(0, 99999999), 8, '0', STR_PAD_LEFT),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_IS_SELLER' => 1,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);

        $buyer = Buyer::create([
            'BUY_ID' => $this->id('BUY'),
            'USR_ID' => $user->USR_ID,
        ]);

        $farmer = Farmer::create([
            'FMR_ID' => $this->id('FMR'),
            'BUY_ID' => $buyer->BUY_ID,
            'FMR_SELLER_MODE_ACTIVE' => 1,
        ]);

        $farm = Farm::create([
            'FRM_ID' => $this->id('FRM'),
            'FRM_NAME' => 'Reyes Farm',
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

    private function payload(array $seller, string $name): array
    {
        $category = CropCategory::first() ?? CropCategory::create([
            'CAT_ID' => $this->id('CAT'), 'CAT_NAME' => 'Vegetables',
        ]);

        return ['farm_id' => $seller['farm']->FRM_ID, 'category_id' => $category->CAT_ID,
            'crop_icon' => $name, 'status' => 'AVAILABLE_NOW'];
    }

    public function test_duplicate_variations_are_rejected_before_upload(): void
    {
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        $this->postJson('/api/listings', $this->payload($seller, 'Cherry Tomato'))->assertCreated();
        foreach ([' cherry tomato ', 'CHERRY TOMATOES', 'Tomatoes - Cherry'] as $name) {
            $this->postJson('/api/listings', $this->payload($seller, $name))
                ->assertUnprocessable()->assertJsonValidationErrors('crop_icon');
        }
        $this->assertDatabaseCount('listing', 1);
        $this->postJson('/api/listings', $this->payload($seller, 'Roma Tomato'))->assertCreated();
    }

    public function test_separate_farms_can_use_the_same_name(): void
    {
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        $this->postJson('/api/listings', $this->payload($seller, 'Tomato'))->assertCreated();
        $farm = $seller['farm']->replicate();
        $farm->FRM_ID = $this->id('FRM');
        $farm->FRM_NAME = 'Second Farm';
        $farm->save();
        $seller['farm'] = $farm;
        $this->postJson('/api/listings', $this->payload($seller, 'Tomatoes'))->assertCreated();
    }

    public function test_edit_cannot_rename_to_a_duplicate_but_can_keep_its_name(): void
    {
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        $this->postJson('/api/listings', $this->payload($seller, 'Tomato'))->assertCreated();
        $id = $this->postJson('/api/listings', $this->payload($seller, 'Carrot'))
            ->assertCreated()->json('listing.id');
        // Use the model primary key; the API formats IDs for older clients too.
        $id = Listing::where('LST_CROP_ICON', 'Carrot')->firstOrFail()->LST_ID;
        $this->patchJson("/api/listings/{$id}", ['crop_icon' => 'Tomatoes'])
            ->assertUnprocessable()->assertJsonValidationErrors('crop_icon');
        $this->patchJson("/api/listings/{$id}", ['crop_icon' => 'Carrot'])->assertOk();
        $this->assertDatabaseHas('listing', ['LST_ID' => $id, 'LST_CROP_ICON' => 'Carrot']);
    }

    public function test_removed_listing_does_not_reserve_the_crop_name(): void
    {
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        $this->postJson('/api/listings', $this->payload($seller, 'Tomato'))->assertCreated();
        Listing::where('FRM_ID', $seller['farm']->FRM_ID)->update(['LST_AVAILABILITY' => Listing::AVAILABILITY_REMOVED]);
        $this->postJson('/api/listings', $this->payload($seller, 'Tomatoes'))->assertCreated();
    }

    public function test_crop_name_assigns_category_when_none_is_sent_and_manual_choice_is_preserved(): void
    {
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        foreach (['Kamatis' => 'LEAFVG', 'Kamote' => 'ROOTCP', 'Rare local crop' => 'OTHERS'] as $name => $category) {
            $payload = $this->payload($seller, $name);
            unset($payload['category_id']);
            $this->postJson('/api/listings', $payload)->assertCreated()->assertJsonPath('listing.category.id', $category);
        }
        $payload = $this->payload($seller, 'Mangga');
        $payload['category_id'] = 'OTHERS';
        $result = $this->postJson('/api/listings', $payload)->assertCreated()->assertJsonPath('listing.category.id', 'OTHERS');
        $id = $result->json('listing.id');
        $this->patchJson("/api/listings/{$id}", ['crop_icon' => 'Banana'])->assertOk()->assertJsonPath('listing.category.id', 'FRUITS');
    }

    public function test_category_catalog_exposes_simple_names_examples_and_local_crop_aliases(): void
    {
        $categories = $this->getJson('/api/crop-categories')->assertOk()->json('categories');
        $vegetables = collect($categories)->firstWhere('id', 'LEAFVG');
        $this->assertSame('Vegetables', $vegetables['name']);
        $this->assertContains('kamatis', $vegetables['crop_names']);
        $this->assertContains('tomatoes', $vegetables['crop_names']);
        $this->assertNotEmpty($vegetables['description']);
        $this->assertNotContains('Legumes', array_column($categories, 'name'));
    }

    public function test_listing_text_limits_reject_oversized_create_and_edit_without_changing_existing_data(): void
    {
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        $payload = $this->payload($seller, str_repeat('A', 41));
        $payload['description'] = str_repeat('D', 1001);
        $this->postJson('/api/listings', $payload)->assertUnprocessable()->assertJsonValidationErrors(['crop_icon', 'description']);
        $this->assertDatabaseCount('listing', 0);
        $payload['crop_icon'] = str_repeat('A', 40);
        $payload['description'] = str_repeat('D', 1000);
        $id = $this->postJson('/api/listings', $payload)->assertCreated()->json('listing.id');
        $this->patchJson("/api/listings/{$id}", ['crop_icon' => str_repeat('B', 41), 'description' => str_repeat('X', 1001)])
            ->assertUnprocessable()->assertJsonValidationErrors(['crop_icon', 'description']);
        $this->assertDatabaseHas('listing', ['LST_ID' => $id, 'LST_CROP_ICON' => str_repeat('A', 40), 'LST_DESCRIPTION' => str_repeat('D', 1000)]);
    }

    public function test_farm_names_descriptions_and_addresses_are_limited_on_the_server(): void
    {
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        $id = $seller['farm']->FRM_ID;
        $this->patchJson("/api/farms/{$id}", ['name' => str_repeat('F', 101), 'description' => str_repeat('D', 1001)])
            ->assertUnprocessable()->assertJsonValidationErrors(['name', 'description']);
        $this->patchJson("/api/farms/{$id}", ['name' => str_repeat('F', 100), 'description' => str_repeat('D', 1000)])->assertOk();
        $this->postJson('/api/farms', ['name' => str_repeat('F', 101), 'description' => str_repeat('D', 1001), 'barangay' => str_repeat('B', 101)])
            ->assertUnprocessable()->assertJsonValidationErrors(['name', 'description', 'barangay']);
        $this->patchJson('/api/user', ['address' => str_repeat('A', 256)])->assertUnprocessable()->assertJsonValidationErrors('address');
        $this->patchJson('/api/user', ['address' => str_repeat('A', 255)])->assertOk();
        $this->postJson('/api/register', ['USR_NAME' => 'Test Person', 'USR_EMAIL' => 'invalid', 'address' => str_repeat('A', 256)])
            ->assertUnprocessable()->assertJsonValidationErrors('address');
    }
}
