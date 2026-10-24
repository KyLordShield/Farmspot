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
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SavedFarmTest extends TestCase
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

    public function test_premium_is_enforced_and_save_retries_do_not_duplicate(): void
    {
        $farm = $this->farm();
        $this->getJson('/api/saved-farms')->assertUnauthorized();
        Sanctum::actingAs($this->account());
        $this->getJson('/api/saved-farms')->assertForbidden();
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertForbidden();
        $user = $this->account(true);
        Sanctum::actingAs($user);
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk()->assertJsonPath('farm.id', $farm->FRM_ID);
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        $this->assertSame(1, DB::table('saved_farm')->where('USR_ID', $user->USR_ID)->count());
        Sanctum::actingAs($user->fresh());
        $this->getJson('/api/saved-farms')->assertOk()->assertJsonCount(1, 'farms')->assertJsonPath('farms.0.name', $farm->FRM_NAME);
    }

    public function test_saves_and_deletes_are_scoped_to_the_account(): void
    {
        $farm = $this->farm();
        $first = $this->account(true);
        $second = $this->account(true);
        Sanctum::actingAs($first);
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID, ['USR_ID' => $second->USR_ID])->assertOk();
        Sanctum::actingAs($second);
        $this->getJson('/api/saved-farms?USR_ID='.$first->USR_ID)->assertJsonCount(0, 'farms');
        $this->deleteJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        $this->assertSame(1, DB::table('saved_farm')->count());
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        $this->deleteJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        Sanctum::actingAs($first);
        $this->getJson('/api/saved-farms')->assertJsonCount(1, 'farms');
    }

    public function test_listings_are_live_and_hidden_crops_are_not_returned(): void
    {
        $farm = $this->farm();
        $crop = $this->listing($farm, 'Cabbage');
        $this->listing($farm, 'Cabbage');
        $this->listing($farm, 'Tomato', 'SOON_TO_HARVEST');
        $this->listing($farm, 'Pechay', 'NOT_AVAILABLE');
        $this->listing($farm, 'Hidden crop', 'AVAILABLE_NOW', 'REMOVED');
        Sanctum::actingAs($this->account(true));
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        $this->getJson('/api/saved-farms')->assertOk()->assertJsonPath('farms.0.available_crops', ['Cabbage'])->assertJsonPath('farms.0.upcoming_crops', ['Tomato']);
        Listing::where('FRM_ID', $farm->FRM_ID)->where('LST_CROP_ICON', 'Cabbage')->update(['LST_STATUS' => 'NOT_AVAILABLE']);
        $this->getJson('/api/saved-farms')->assertJsonPath('farms.0.available_crops', []);
    }

    public function test_unavailable_farms_are_redacted_and_removable(): void
    {
        $farm = $this->farm();
        Sanctum::actingAs($this->account(true));
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        $farm->FRM_STATUS = 'ARCHIVED';
        $farm->save();
        $this->getJson('/api/saved-farms')->assertOk()->assertJsonPath('farms.0.available', false)->assertJsonPath('farms.0.name', 'Farm unavailable')->assertJsonMissingPath('farms.0.latitude')->assertJsonMissingPath('farms.0.photo_url');
        $this->deleteJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        $this->assertSame(0, DB::table('saved_farm')->count());
    }

    public function test_premium_expiry_preserves_saves_and_cleanup_is_allowed(): void
    {
        $farm = $this->farm();
        $user = $this->account(true);
        Sanctum::actingAs($user);
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        $user->USR_PREMIUM_EXPIRES_AT = now()->subDay();
        $user->save();
        Sanctum::actingAs($user->fresh());
        $this->getJson('/api/saved-farms')->assertForbidden();
        $this->assertSame(1, DB::table('saved_farm')->count());
        $user->USR_PREMIUM_EXPIRES_AT = now()->addMonth();
        $user->save();
        Sanctum::actingAs($user->fresh());
        $this->getJson('/api/saved-farms')->assertJsonCount(1, 'farms');
        $user->USR_PREMIUM_EXPIRES_AT = now()->subDay();
        $user->save();
        Sanctum::actingAs($user->fresh());
        $this->deleteJson('/api/saved-farms/'.$farm->FRM_ID)->assertOk();
        $this->assertSame(0, DB::table('saved_farm')->count());
    }

    public function test_unapproved_or_inactive_seller_farms_cannot_be_saved(): void
    {
        $farm = $this->farm();
        Sanctum::actingAs($this->account(true));
        $farm->FRM_STATUS = 'PENDING_REVIEW';
        $farm->save();
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertNotFound();
        $farm->FRM_STATUS = 'APPROVED';
        $farm->save();
        $owner = $farm->farmer->buyer->user;
        $owner->USR_STATUS = 'DEACTIVATED';
        $owner->save();
        $this->putJson('/api/saved-farms/'.$farm->FRM_ID)->assertNotFound();
        $this->putJson('/api/saved-farms/XXXXXX')->assertNotFound();
        $this->assertSame(0, DB::table('saved_farm')->count());
    }
}
