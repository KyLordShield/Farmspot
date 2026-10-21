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

/**
 * The hourly expiry command reports an on-sale listing's ended window without
 * removing it from the buyer-facing feed.
 *
 * A SOON_TO_HARVEST crop has not started its three-day window yet, so the
 * expiry stamped when it was posted must not be reported while the harvest is
 * still ahead. listings:harvest starts that window when the date arrives.
 */
class ExpireListingsTest extends TestCase
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
            'USR_EMAIL' => 'expire'.Str::lower(Str::random(6)).'@test.local',
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

    private function makeListing(
        array $seller,
        string $status,
        \DateTimeInterface $expiry,
    ): Listing {
        $categoryId = CropCategory::first()?->CAT_ID
            ?? CropCategory::create([
                'CAT_ID' => $this->id('CAT'),
                'CAT_NAME' => 'Vegetables',
            ])->CAT_ID;

        return Listing::create([
            'LST_ID' => $this->id('LST'),
            'LST_CROP_ICON' => 'Carrot',
            'LST_STATUS' => $status,
            'LST_AVAILABILITY' => 'ACTIVE',
            'LST_EXPIRY_DATE' => $expiry,
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $seller['farmer']->FMR_ID,
            'FRM_ID' => $seller['farm']->FRM_ID,
            'CAT_ID' => $categoryId,
        ]);
    }

    public function test_an_expired_on_sale_listing_stays_available_for_buyers(): void
    {
        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'AVAILABLE_NOW', now()->subDay());

        $this->artisan('listings:expire')->assertSuccessful();

        $this->assertSame('AVAILABLE_NOW', $listing->fresh()->LST_STATUS);
    }

    public function test_a_soon_to_harvest_listing_is_not_expired(): void
    {
        $seller = $this->makeSeller();
        $listing = $this->makeListing(
            $seller,
            'SOON_TO_HARVEST',
            now()->subDay()
        );

        $this->artisan('listings:expire')->assertSuccessful();

        $this->assertSame('SOON_TO_HARVEST', $listing->fresh()->LST_STATUS);
    }
}
