<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\AdminMfa;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class AdminListingPhotoTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'photo_test',
            'database.connections.photo_test' => ['driver' => 'sqlite', 'database' => ':memory:'],
            'cache.default' => 'array']);
        DB::purge('photo_test');
        foreach ([
            'user' => ['USR_ID', 'USR_NAME', 'USR_EMAIL', 'USR_PASSWORD', 'USR_ROLE', 'USR_STATUS'],
            'buyer' => ['BUY_ID', 'USR_ID'], 'farmer' => ['FMR_ID', 'BUY_ID'],
            'farm' => ['FRM_ID', 'FMR_ID', 'FRM_NAME', 'FRM_BARANGAY'],
            'crop_category' => ['CAT_ID', 'CAT_NAME'],
            'listing' => ['LST_ID', 'FMR_ID', 'FRM_ID', 'CAT_ID', 'LST_CROP_ICON', 'LST_DESCRIPTION', 'LST_STATUS', 'LST_AVAILABILITY', 'LST_IMAGE', 'LST_CREATED_AT', 'LST_UPDATED_AT', 'LST_EXPIRY_DATE', 'LST_HARVEST_DATE'],
            'listing_photo' => ['LPHOTO_ID', 'LST_ID', 'LPHOTO_FILE_PATH', 'LPHOTO_IS_PRIMARY', 'LPHOTO_UPLOADED_AT'],
        ] as $table => $columns) {
            Schema::create($table, function (Blueprint $blueprint) use ($columns) {
                foreach ($columns as $column) $blueprint->string($column)->nullable();
                $blueprint->primary($columns[0]);
            });
        }
        Http::preventStrayRequests();
        Storage::fake('cloudinary');
        $admin = User::create(['USR_ID' => 'ADMIN1', 'USR_NAME' => 'Listing Admin', 'USR_EMAIL' => 'admin@example.test',
            'USR_PASSWORD' => bcrypt('password'), 'USR_ROLE' => 'ADMIN', 'USR_STATUS' => 'ACTIVE']);
        $this->actingAs($admin)->withSession(['admin_mfa' => [
            'verified' => app(AdminMfa::class)->fingerprint($admin), 'started' => now()->timestamp, 'last_seen' => now()->timestamp,
        ]]);
        DB::table('buyer')->insert(['BUY_ID' => 'BUY001', 'USR_ID' => 'ADMIN1']);
        DB::table('farmer')->insert(['FMR_ID' => 'FMR001', 'BUY_ID' => 'BUY001']);
        DB::table('farm')->insert(['FRM_ID' => 'FRM001', 'FMR_ID' => 'FMR001', 'FRM_NAME' => 'Test Farm', 'FRM_BARANGAY' => 'Pusok']);
        DB::table('crop_category')->insert(['CAT_ID' => 'VEG001', 'CAT_NAME' => 'Vegetables']);
        DB::table('listing')->insert(['LST_ID' => 'LST001', 'FRM_ID' => 'FRM001', 'FMR_ID' => 'FMR001', 'CAT_ID' => 'VEG001',
            'LST_CROP_ICON' => 'Cabbage', 'LST_DESCRIPTION' => 'Fresh cabbage', 'LST_STATUS' => 'AVAILABLE_NOW', 'LST_AVAILABILITY' => 'ACTIVE',
            'LST_CREATED_AT' => now()->toDateTimeString(), 'LST_EXPIRY_DATE' => now()->addDays(3)->toDateTimeString()]);
    }

    private function photo(int $number, string $listing = 'LST001'): string
    {
        $id = 'PH'.str_pad((string) $number, 4, '0', STR_PAD_LEFT);
        $path = 'listing-photos/'.$listing.'/'.$id.'.png';
        $url = 'https://res.cloudinary.com/test/image/upload/v1/'.$path;
        Storage::disk('cloudinary')->put($path, 'photo');
        DB::table('listing_photo')->insert(['LPHOTO_ID' => $id, 'LST_ID' => $listing, 'LPHOTO_FILE_PATH' => $url,
            'LPHOTO_IS_PRIMARY' => $number === 1 ? 1 : 0, 'LPHOTO_UPLOADED_AT' => now()->toDateTimeString()]);
        if ($number === 1) DB::table('listing')->where('LST_ID', $listing)->update(['LST_IMAGE' => $url]);
        return $url;
    }

    private function payload(array $extra = []): array
    {
        return array_merge(['LST_CROP_ICON' => 'Cabbage', 'CAT_ID' => 'VEG001', 'LST_STATUS' => 'AVAILABLE_NOW', 'LST_AVAILABILITY' => 'ACTIVE'], $extra);
    }

    private function upload(): UploadedFile
    {
        return UploadedFile::fake()->createWithContent('replacement.png', base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
    }

    public function test_edit_page_offers_removal_and_details_render(): void
    {
        $this->photo(1);
        $this->get('/listings/LST001/edit')->assertOk()->assertSee('name="remove_photos[]"', false)->assertSee('Save Changes');
        $this->get('/listings/LST001')->assertOk()->assertSee('Fresh cabbage')->assertSee('Test Farm');
    }

    public function test_deleting_cover_promotes_remaining_photo_and_cleans_storage(): void
    {
        $this->photo(1);
        $second = $this->photo(2);
        $this->put('/listings/LST001', $this->payload(['remove_photos' => ['PH0001']]))->assertRedirect('/listings/LST001');
        $this->assertDatabaseMissing('listing_photo', ['LPHOTO_ID' => 'PH0001']);
        $this->assertDatabaseHas('listing_photo', ['LPHOTO_ID' => 'PH0002', 'LPHOTO_IS_PRIMARY' => 1]);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST001', 'LST_IMAGE' => $second]);
        Storage::disk('cloudinary')->assertMissing('listing-photos/LST001/PH0001.png');
    }

    public function test_all_photos_can_be_removed_without_a_legacy_image_reappearing(): void
    {
        $url = $this->photo(1);
        $this->put('/listings/LST001', $this->payload(['remove_photos' => ['PH0001']]))->assertRedirect('/listings/LST001');
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST001', 'LST_IMAGE' => null]);
        $this->assertDatabaseCount('listing_photo', 0);
        $this->get('/listings/LST001')->assertOk()->assertDontSee($url);
    }

    public function test_legacy_cover_can_be_removed(): void
    {
        $url = 'https://res.cloudinary.com/test/image/upload/v1/listing-photos/legacy.png';
        DB::table('listing')->where('LST_ID', 'LST001')->update(['LST_IMAGE' => $url]);
        $this->get('/listings/LST001/edit')->assertOk()->assertSee('name="remove_legacy_photo"', false);
        $this->put('/listings/LST001', $this->payload(['remove_legacy_photo' => '1']))->assertRedirect('/listings/LST001');
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST001', 'LST_IMAGE' => null]);
    }

    public function test_full_gallery_allows_a_replacement_in_the_same_save(): void
    {
        for ($i = 1; $i <= 5; $i++) $this->photo($i);
        $this->put('/listings/LST001', $this->payload(['remove_photos' => ['PH0001'], 'photos' => [$this->upload()]]))
            ->assertRedirect('/listings/LST001')->assertSessionHasNoErrors();
        $this->assertDatabaseCount('listing_photo', 5);
        $this->assertDatabaseMissing('listing_photo', ['LPHOTO_ID' => 'PH0001']);
        $this->assertSame(1, DB::table('listing_photo')->where('LPHOTO_IS_PRIMARY', 1)->count());
    }

    public function test_exceeding_limit_rolls_back_removal_and_preserves_files(): void
    {
        $original = $this->photo(1);
        for ($i = 2; $i <= 5; $i++) $this->photo($i);
        $this->put('/listings/LST001', $this->payload(['remove_photos' => ['PH0001'], 'photos' => [$this->upload(), $this->upload()]]))
            ->assertSessionHasErrors('photos');
        $this->assertDatabaseCount('listing_photo', 5);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST001', 'LST_IMAGE' => $original]);
        Storage::disk('cloudinary')->assertExists('listing-photos/LST001/PH0001.png');
    }

    public function test_upload_failure_rolls_back_photo_removal(): void
    {
        $original = $this->photo(1);
        $disk = Storage::disk('cloudinary');
        $failing = \Mockery::mock(\Illuminate\Filesystem\FilesystemAdapter::class);
        $failing->shouldReceive('put')->once()->andReturn(false);
        Storage::shouldReceive('disk')->with('cloudinary')->andReturn($failing);
        $this->put('/listings/LST001', $this->payload(['remove_photos' => ['PH0001'], 'photos' => [$this->upload()]]))
            ->assertSessionHasErrors('photos');
        $this->assertDatabaseHas('listing_photo', ['LPHOTO_ID' => 'PH0001', 'LPHOTO_IS_PRIMARY' => 1]);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST001', 'LST_IMAGE' => $original]);
        $disk->assertExists('listing-photos/LST001/PH0001.png');
    }

    public function test_shared_legacy_asset_is_not_deleted_from_storage(): void
    {
        $this->photo(1);
        $other = (array) DB::table('listing')->where('LST_ID', 'LST001')->first();
        $other['LST_ID'] = 'OTHER1';
        DB::table('listing')->insert($other);
        $this->put('/listings/LST001', $this->payload(['remove_photos' => ['PH0001']]))->assertRedirect('/listings/LST001');
        $this->assertDatabaseMissing('listing_photo', ['LPHOTO_ID' => 'PH0001']);
        Storage::disk('cloudinary')->assertExists('listing-photos/LST001/PH0001.png');
    }

    public function test_foreign_photos_are_rejected_without_changing_the_gallery(): void
    {
        $original = $this->photo(1);
        $this->photo(2, 'OTHER1');
        $this->put('/listings/LST001', $this->payload(['remove_photos' => ['PH0002']]))->assertSessionHasErrors('remove_photos');
        $this->assertDatabaseCount('listing_photo', 2);
        $this->assertDatabaseHas('listing', ['LST_ID' => 'LST001', 'LST_IMAGE' => $original]);
    }
}
