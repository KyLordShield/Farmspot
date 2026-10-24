<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SourcingTest extends TestCase
{
    use RefreshDatabase;

    private function account(bool $premium = false): User
    {
        $id = strtoupper(Str::random(6));
        $user = User::create(['USR_ID' => $id, 'USR_NAME' => 'Save Test', 'USR_EMAIL' => strtolower($id).'@saved.test', 'USR_PASSWORD' => bcrypt('password123'), 'USR_MOBILE_NUMBER' => '09'.random_int(1000000000, 9999999999), 'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE', 'USR_IS_SELLER' => 0, 'USR_CREATED_AT' => now()]);
        if ($premium) {
            $user->USR_PREMIUM_EXPIRES_AT = now()->addMonth();
            $user->save();
        }

        return $user;
    }

    private function farm(): Farm
    {
        $owner = $this->account();
        $owner->USR_IS_SELLER = 1;
        $owner->save();
        $buyer = Buyer::create(['BUY_ID' => strtoupper(Str::random(6)), 'USR_ID' => $owner->USR_ID]);
        $farmer = Farmer::create(['FMR_ID' => strtoupper(Str::random(6)), 'BUY_ID' => $buyer->BUY_ID, 'FMR_SELLER_MODE_ACTIVE' => 1]);

        return Farm::create(['FRM_ID' => strtoupper(Str::random(6)), 'FMR_ID' => $farmer->FMR_ID, 'FRM_NAME' => 'Saved Test Farm', 'FRM_BARANGAY' => 'Sudlon', 'FRM_LATITUDE' => 10.3, 'FRM_LONGITUDE' => 123.9, 'FRM_STATUS' => 'APPROVED', 'FRM_PIN_ACTIVE' => 1, 'FRM_CREATED_AT' => now()]);
    }

    private function listing(Farm $farm, string $crop, string $status = 'AVAILABLE_NOW', string $availability = 'ACTIVE'): Listing
    {
        $category = CropCategory::first() ?? CropCategory::create(['CAT_ID' => strtoupper(Str::random(6)), 'CAT_NAME' => 'Vegetables']);

        return Listing::create(['LST_ID' => strtoupper(Str::random(6)), 'FMR_ID' => $farm->FMR_ID, 'FRM_ID' => $farm->FRM_ID, 'CAT_ID' => $category->CAT_ID, 'LST_CROP_ICON' => $crop, 'LST_STATUS' => $status, 'LST_AVAILABILITY' => $availability, 'LST_CREATED_AT' => now(), 'LST_UPDATED_AT' => now()]);
    }

    public function test_lists_are_premium_scoped_and_persist_without_touching_other_accounts(): void
    {
        $this->getJson('/api/sourcing/list')->assertUnauthorized();
        Sanctum::actingAs($this->account());
        $this->putJson('/api/sourcing/list', ['crops' => ['Cabbage']])->assertForbidden();
        $first = $this->account(true);
        $second = $this->account(true);
        Sanctum::actingAs($first);
        $this->putJson('/api/sourcing/list', ['crops' => ['Cabbage', 'Tomato'], 'USR_ID' => $second->USR_ID])->assertOk();
        $this->getJson('/api/sourcing/list')->assertJsonPath('crops', ['Cabbage', 'Tomato'])->assertJsonPath('crop_aliases.Tomato', ['kamatis']);
        Sanctum::actingAs($second);
        $this->getJson('/api/sourcing/list')->assertJsonPath('crops', []);
        $this->putJson('/api/sourcing/list', ['crops' => ['unrecognized crop']])->assertUnprocessable();
        Sanctum::actingAs($first);
        $this->putJson('/api/sourcing/list', ['crops' => []])->assertOk();
        $this->getJson('/api/sourcing/list')->assertJsonPath('crops', []);
    }

    public function test_matches_aliases_includes_distant_farms_and_identifies_missing_crops(): void
    {
        $near = $this->farm();
        $far = $this->farm();
        $far->update(['FRM_LATITUDE' => 16.4, 'FRM_LONGITUDE' => 120.6]);
        $this->listing($near, 'Kamatis')->update(['LST_EXPIRY_DATE' => now()->addDays(2)]);
        $this->listing($far, 'Repolyo')->update(['LST_EXPIRY_DATE' => now()->subDay()]);
        $this->listing($near, 'Pechay', 'SOON_TO_HARVEST');
        $this->listing($near, 'Okra', 'NOT_AVAILABLE');
        $this->listing($near, 'Okra', 'SOON_TO_HARVEST', 'REMOVED');
        $this->listing($near, 'Pechay', 'NOT_AVAILABLE');
        $this->listing($near, 'Pechay', 'AVAILABLE_NOW', 'REMOVED');
        Sanctum::actingAs($this->account(true));
        $this->putJson('/api/sourcing/list', ['crops' => ['Tomato', 'Cabbage', 'Pechay', 'Okra']])->assertOk();
        $this->postJson('/api/sourcing/matches', ['latitude' => 10.3, 'longitude' => 123.9, 'radius' => 1])
            ->assertOk()->assertJsonCount(2, 'farms')->assertJsonPath('farms.0.id', $near->FRM_ID)
            ->assertJsonPath('farms.0.matched_crops', ['Tomato', 'Pechay'])->assertJsonPath('farms.0.available_crops', ['Tomato'])->assertJsonPath('farms.0.upcoming_crops', ['Pechay'])->assertJsonPath('farms.0.needs_confirmation', false)
            ->assertJsonPath('farms.1.id', $far->FRM_ID)->assertJsonPath('farms.1.needs_confirmation', true)
            ->assertJsonPath('missing_crops', ['Okra']);
        $far->update(['FRM_STATUS' => 'ARCHIVED']);
        $this->postJson('/api/sourcing/matches')->assertJsonCount(1, 'farms')->assertJsonPath('has_buyer_location', false)->assertJsonPath('farms.0.distance_km', null)->assertJsonPath('missing_crops', ['Cabbage', 'Okra']);
        $this->postJson('/api/sourcing/matches', ['latitude' => 10])->assertUnprocessable();
    }

    public function test_custom_saved_crops_remain_when_stock_is_removed(): void
    {
        $farm = $this->farm();
        $listing = $this->listing($farm, 'Local Special Crop');
        Sanctum::actingAs($this->account(true));
        $this->putJson('/api/sourcing/list', ['crops' => ['Local Special Crop']])->assertOk();
        $listing->update(['LST_AVAILABILITY' => 'REMOVED']);
        $this->putJson('/api/sourcing/list', ['crops' => ['Local Special Crop']])->assertOk();
        $this->postJson('/api/sourcing/matches')->assertOk()->assertJsonCount(0, 'farms')->assertJsonPath('missing_crops', ['Local Special Crop']);
    }
}
