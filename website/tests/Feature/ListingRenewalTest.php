<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\Listing;
use App\Models\ListingPhoto;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Renewal is the only path allowed to extend a listing's three-day window.
 *
 * A normal status update or edit must never buy another three days, or a seller
 * can keep a stale listing alive by re-tapping the status it already has. The
 * renewal itself is a separate multipart endpoint because it is a claim that
 * the crop is still available and therefore needs a fresh photo.
 */
class ListingRenewalTest extends TestCase
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

    private function makeListing(
        array $seller,
        string $status = 'AVAILABLE_NOW',
        \DateTimeInterface $expiry,
        string $availability = 'ACTIVE',
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
            'LST_AVAILABILITY' => $availability,
            'LST_EXPIRY_DATE' => $expiry,
            'LST_CREATED_AT' => now(),
            'LST_UPDATED_AT' => now(),
            'FMR_ID' => $seller['farmer']->FMR_ID,
            'FRM_ID' => $seller['farm']->FRM_ID,
            'CAT_ID' => $categoryId,
        ]);
    }

    private function pngUpload(): UploadedFile
    {
        static $path;

        if ($path === null) {
            $path = tempnam(sys_get_temp_dir(), 'renew_').'.png';
            file_put_contents(
                $path,
                base64_decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
                    .'/x8AAwMCAO+/p9sAAAAASUVORK5CYII='
                )
            );
        }

        return new UploadedFile($path, 'fresh.png', 'image/png', null, true);
    }

    private function renew(Listing $listing, array $data = []): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($listing->farmer->buyer->user, 'sanctum')
            ->post("/api/listings/{$listing->LST_ID}/renew", $data, [
                'Accept' => 'application/json',
            ]);
    }

    public function test_a_status_update_cannot_extend_an_expired_listing(): void
    {
        $seller = $this->makeSeller();
        $expiry = now()->subDay()->startOfSecond();
        $listing = $this->makeListing($seller, 'AVAILABLE_NOW', $expiry);

        $this->actingAs($seller['user'], 'sanctum')
            ->patchJson("/api/listings/{$listing->LST_ID}/status", [
                'status' => 'AVAILABLE_NOW',
            ])
            ->assertStatus(422)
            ->assertJson([
                'message' => 'This listing has expired. Renew it with a fresh photo to show it again.',
            ]);

        $this->assertSame(
            $expiry->toDateTimeString(),
            $listing->fresh()->LST_EXPIRY_DATE
        );
    }

    public function test_a_status_change_cannot_revive_an_expired_listing(): void
    {
        $seller = $this->makeSeller();
        $expiry = now()->subDay()->startOfSecond();
        $listing = $this->makeListing($seller, 'NOT_AVAILABLE', $expiry);

        $this->actingAs($seller['user'], 'sanctum')
            ->patchJson("/api/listings/{$listing->LST_ID}/status", [
                'status' => 'AVAILABLE_NOW',
            ])
            ->assertStatus(422);

        $fresh = $listing->fresh();
        $this->assertSame('NOT_AVAILABLE', $fresh->LST_STATUS);
        $this->assertSame($expiry->toDateTimeString(), $fresh->LST_EXPIRY_DATE);
    }

    public function test_an_edit_does_not_extend_an_expired_listing(): void
    {
        $seller = $this->makeSeller();
        $expiry = now()->subDay()->startOfSecond();
        $listing = $this->makeListing($seller, 'AVAILABLE_NOW', $expiry);

        $this->actingAs($seller['user'], 'sanctum')
            ->patchJson("/api/listings/{$listing->LST_ID}", [
                'description' => 'Corrected the description only.',
            ])
            ->assertOk();

        $this->assertSame(
            $expiry->toDateTimeString(),
            $listing->fresh()->LST_EXPIRY_DATE
        );
    }

    public function test_a_live_status_change_does_not_extend_the_window(): void
    {
        $seller = $this->makeSeller();
        $expiry = now()->addDays(2)->startOfSecond();
        $listing = $this->makeListing($seller, 'AVAILABLE_NOW', $expiry);

        $this->actingAs($seller['user'], 'sanctum')
            ->patchJson("/api/listings/{$listing->LST_ID}/status", [
                'status' => 'NOT_AVAILABLE',
            ])
            ->assertOk();

        $this->assertSame(
            $expiry->toDateTimeString(),
            $listing->fresh()->LST_EXPIRY_DATE
        );
    }

    public function test_renewal_requires_a_photo(): void
    {
        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'NOT_AVAILABLE', now()->subDay());

        $this->renew($listing, ['status' => 'AVAILABLE_NOW'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');
    }

    public function test_renewal_requires_a_harvest_date_when_the_crop_is_not_ready(): void
    {
        Storage::fake('cloudinary');

        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'NOT_AVAILABLE', now()->subDay());

        $this->renew($listing, [
            'status' => 'SOON_TO_HARVEST',
            'photo' => $this->pngUpload(),
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('harvest_date');
    }

    public function test_renewal_records_the_fresh_photo_and_extends_the_window(): void
    {
        Storage::fake('cloudinary');

        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'NOT_AVAILABLE', now()->subDay());

        $response = $this->renew($listing, [
            'status' => 'AVAILABLE_NOW',
            'photo' => $this->pngUpload(),
        ]);

        $response->assertOk()
            ->assertJsonPath('listing.status', 'AVAILABLE_NOW')
            ->assertJsonPath('listing.renewal_count', 1);

        $fresh = $listing->fresh();
        $this->assertSame('AVAILABLE_NOW', $fresh->LST_STATUS);
        $this->assertSame(1, (int) $fresh->LST_RENEWAL_COUNT);
        $this->assertNotNull($fresh->LST_LAST_RENEWED_AT);
        $this->assertNotNull($fresh->LST_IMAGE);
        $this->assertTrue(
            now()->addDays(2)->lessThan($fresh->LST_EXPIRY_DATE),
            'Renewal must give the listing a new three-day window.'
        );

        $this->assertDatabaseHas('listing_photo', [
            'LST_ID' => $listing->LST_ID,
            'LPHOTO_IS_PRIMARY' => 1,
        ]);
    }

    public function test_a_live_listing_cannot_be_renewed_early(): void
    {
        Storage::fake('cloudinary');

        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'AVAILABLE_NOW', now()->addDays(2));

        $this->renew($listing, [
            'status' => 'AVAILABLE_NOW',
            'photo' => $this->pngUpload(),
        ])->assertStatus(422);

        $fresh = $listing->fresh();
        $this->assertSame(0, (int) $fresh->LST_RENEWAL_COUNT);
        $this->assertNull($fresh->LST_LAST_RENEWED_AT);
    }

    public function test_a_removed_listing_cannot_be_renewed(): void
    {
        $seller = $this->makeSeller();
        $listing = $this->makeListing(
            $seller,
            'NOT_AVAILABLE',
            now()->subDay(),
            'REMOVED'
        );

        $this->renew($listing, [
            'status' => 'AVAILABLE_NOW',
            'photo' => $this->pngUpload(),
        ])
            ->assertStatus(403)
            ->assertJson([
                'message' => 'This listing was removed and can no longer be edited.',
            ]);

        $this->assertSame(0, (int) $listing->fresh()->LST_RENEWAL_COUNT);
    }

    public function test_renewal_replaces_every_old_photo_and_chooses_the_primary(): void
    {
        Storage::fake('cloudinary');

        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'NOT_AVAILABLE', now()->subDay());

        $oldUrls = [];
        foreach (range(1, 3) as $i) {
            $url = "https://res.cloudinary.com/test/image/upload/v1/listing-photos/{$listing->LST_ID}/old-{$i}.jpg";
            $oldUrls[] = $url;

            ListingPhoto::create([
                'LPHOTO_ID' => sprintf('OLD%03d', $i),
                'LPHOTO_FILE_PATH' => $url,
                'LPHOTO_UPLOADED_AT' => now()->subDays(4),
                'LPHOTO_IS_PRIMARY' => $i === 1 ? 1 : 0,
                'LST_ID' => $listing->LST_ID,
            ]);
        }

        $listing->LST_IMAGE = $oldUrls[0];
        $listing->save();

        $response = $this->renew($listing, [
            'status' => 'AVAILABLE_NOW',
            'photos' => [$this->pngUpload(), $this->pngUpload(), $this->pngUpload()],
            'primary_index' => 1,
        ]);

        $response->assertOk()
            ->assertJsonCount(3, 'listing.photos');

        $fresh = $listing->fresh();

        $this->assertNotContains($fresh->LST_IMAGE, $oldUrls);

        foreach ($oldUrls as $oldUrl) {
            $this->assertDatabaseMissing('listing_photo', [
                'LST_ID' => $listing->LST_ID,
                'LPHOTO_FILE_PATH' => $oldUrl,
            ]);
        }

        $photos = ListingPhoto::where('LST_ID', $listing->LST_ID)->get();
        $this->assertCount(3, $photos);

        $primary = $photos->firstWhere('LPHOTO_IS_PRIMARY', 1);
        $this->assertNotNull($primary);
        $this->assertSame($fresh->LST_IMAGE, $primary->LPHOTO_FILE_PATH);
        $this->assertNotContains($primary->LPHOTO_FILE_PATH, $oldUrls);
    }

    public function test_a_soon_to_harvest_listing_cannot_be_renewed_early(): void
    {
        Storage::fake('cloudinary');

        $seller = $this->makeSeller();
        // The creation-time expiry is in the past, but the crop is still
        // upcoming, so its on-sale window never started.
        $listing = $this->makeListing(
            $seller,
            'SOON_TO_HARVEST',
            now()->subDay()
        );

        $this->renew($listing, [
            'status' => 'AVAILABLE_NOW',
            'photo' => $this->pngUpload(),
        ])->assertStatus(422);

        $this->assertSame(0, (int) $listing->fresh()->LST_RENEWAL_COUNT);
    }
}
