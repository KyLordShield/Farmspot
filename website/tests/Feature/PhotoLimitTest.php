<?php

namespace Tests\Feature;

use App\Models\Buyer;
use App\Models\CropCategory;
use App\Models\Farm;
use App\Models\Farmer;
use App\Models\FarmPhoto;
use App\Models\Listing;
use App\Models\ListingPhoto;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Tests\TestCase;

class PhotoLimitTest extends TestCase
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
        string $status,
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

    private function farmPhotos(array $seller, int $count): void
    {
        for ($i = 1; $i <= $count; $i++) {
            FarmPhoto::create([
                'FPHOTO_ID' => sprintf('P%05d', $i), 'FRM_ID' => $seller['farm']->FRM_ID,
                'FPHOTO_FILE_PATH' => "https://example.test/farm{$i}.png", 'FPHOTO_UPLOADED_AT' => now(), 'FPHOTO_IS_PRIMARY' => $i === 1,
            ]);
        }
    }

    private function listingPhotos(Listing $listing, int $count): void
    {
        for ($i = 1; $i <= $count; $i++) {
            ListingPhoto::create([
                'LPHOTO_ID' => sprintf('P%05d', $i), 'LST_ID' => $listing->LST_ID,
                'LPHOTO_FILE_PATH' => "https://example.test/crop{$i}.png", 'LPHOTO_UPLOADED_AT' => now(), 'LPHOTO_IS_PRIMARY' => $i === 1,
            ]);
        }
    }

    public function test_farm_gallery_counts_existing_photos_and_allows_a_replacement_after_removal(): void
    {
        Storage::fake('cloudinary');
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        $this->farmPhotos($seller, 4);
        $id = $seller['farm']->FRM_ID;
        $this->post("/api/farms/{$id}/photos", ['photos' => [$this->pngUpload()]], ['Accept' => 'application/json'])
            ->assertUnprocessable()->assertJsonValidationErrors('photos');
        $this->assertCount(0, Storage::disk('cloudinary')->allFiles());
        $this->deleteJson("/api/farms/{$id}/photos/P00004")->assertOk();
        $this->post("/api/farms/{$id}/photos", ['photos' => [$this->pngUpload()]], ['Accept' => 'application/json'])->assertOk();
        $this->assertSame(4, FarmPhoto::where('FRM_ID', $id)->count());
    }

    public function test_farm_creation_refuses_more_than_four_photos(): void
    {
        Storage::fake('cloudinary');
        $seller = $this->makeSeller();
        $this->actingAs($seller['user'], 'sanctum');
        $payload = ['name' => 'Another Farm', 'barangay' => 'Pusok', 'latitude' => 10.3, 'longitude' => 123.9,
            'photos' => array_map(fn () => $this->pngUpload(), range(1, 5))];
        $this->post('/api/farms', $payload, ['Accept' => 'application/json'])->assertUnprocessable()->assertJsonValidationErrors('photos');
        $this->assertDatabaseCount('farm', 1);
        $this->assertCount(0, Storage::disk('cloudinary')->allFiles());
        array_pop($payload['photos']);
        $this->post('/api/farms', $payload, ['Accept' => 'application/json'])->assertCreated();
        $this->assertDatabaseCount('farm_photo', 4);
    }

    public function test_listing_gallery_refuses_total_over_five_even_with_small_upload_requests(): void
    {
        Storage::fake('cloudinary');
        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'AVAILABLE_NOW', now()->addDay());
        $this->listingPhotos($listing, 4);
        $this->actingAs($seller['user'], 'sanctum');
        $id = $listing->LST_ID;
        $this->post("/api/listings/{$id}/photos", ['photos' => [$this->pngUpload(), $this->pngUpload()]], ['Accept' => 'application/json'])
            ->assertUnprocessable()->assertJsonValidationErrors('photos');
        $this->assertCount(0, Storage::disk('cloudinary')->allFiles());
        $this->post("/api/listings/{$id}/photos", ['photos' => [$this->pngUpload()]], ['Accept' => 'application/json'])->assertCreated();
        $this->post("/api/listings/{$id}/photos", ['photos' => [$this->pngUpload()]], ['Accept' => 'application/json'])
            ->assertUnprocessable()->assertJsonValidationErrors('photos');
        $this->assertSame(5, ListingPhoto::where('LST_ID', $id)->count());
    }

    public function test_renewal_replaces_gallery_but_refuses_six_fresh_photos(): void
    {
        Storage::fake('cloudinary');
        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'NOT_AVAILABLE', now()->subDay());
        $this->listingPhotos($listing, 5);
        $this->actingAs($seller['user'], 'sanctum');
        $id = $listing->LST_ID;
        $uploads = array_map(fn () => $this->pngUpload(), range(1, 6));
        $this->post("/api/listings/{$id}/renew", ['status' => 'AVAILABLE_NOW', 'photos' => $uploads], ['Accept' => 'application/json'])
            ->assertUnprocessable()->assertJsonValidationErrors('photos');
        $this->assertSame(5, ListingPhoto::where('LST_ID', $id)->count());
        $this->assertCount(0, Storage::disk('cloudinary')->allFiles());
        array_pop($uploads);
        $this->post("/api/listings/{$id}/renew", ['status' => 'AVAILABLE_NOW', 'photos' => $uploads], ['Accept' => 'application/json'])->assertOk();
        $this->assertSame(5, ListingPhoto::where('LST_ID', $id)->count());
    }

    public function test_legacy_primary_replacement_keeps_a_full_gallery_at_five(): void
    {
        Storage::fake('cloudinary');
        $seller = $this->makeSeller();
        $listing = $this->makeListing($seller, 'AVAILABLE_NOW', now()->addDay());
        $this->listingPhotos($listing, 5);
        $this->actingAs($seller['user'], 'sanctum');
        $this->post("/api/listings/{$listing->LST_ID}/photo", ['photo' => $this->pngUpload()], ['Accept' => 'application/json'])->assertOk();
        $this->assertSame(5, ListingPhoto::where('LST_ID', $listing->LST_ID)->count());
    }
}
