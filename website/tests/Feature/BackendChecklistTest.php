<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Report;
use App\Services\MassReportService;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Http\Middleware\ValidateCsrfToken;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

/** Synthetic request checks only: in-memory SQLite, no migrations or external storage. */
class BackendChecklistTest extends SecurityAuditObservationTest
{
    protected function setUp(): void
    {
        parent::setUp();
        foreach ([
            'farmer' => ['FMR_ID', 'BUY_ID', 'FMR_SELLER_MODE_ACTIVE'],
            'farm' => ['FRM_ID', 'FMR_ID', 'FRM_NAME', 'FRM_STATUS', 'FRM_PIN_ACTIVE', 'FRM_CREATED_AT'],
            'crop_category' => ['CAT_ID', 'CAT_NAME', 'CAT_ICON', 'CAT_DESCRIPTION'],
            'listing' => ['LST_ID', 'FMR_ID', 'FRM_ID', 'CAT_ID', 'LST_CROP_ICON', 'LST_DESCRIPTION', 'LST_STATUS', 'LST_AVAILABILITY', 'LST_CREATED_AT', 'LST_UPDATED_AT', 'LST_HARVEST_DATE', 'LST_EXPIRY_DATE', 'LST_IMAGE'],
            'listing_photo' => ['LPHOTO_ID', 'LST_ID', 'LPHOTO_UPLOADED_AT', 'LPHOTO_FILE_PATH', 'LPHOTO_IS_PRIMARY'],
            'listing_review' => ['LRV_ID', 'LST_ID', 'USR_ID', 'LRV_STATUS', 'LRV_RATING', 'LRV_COMMENT', 'LRV_CREATED_AT', 'LRV_UPDATED_AT'],
            'report' => ['RPT_ID', 'USR_ID', 'LST_ID', 'RPT_STATUS', 'RPT_TARGET_TYPE', 'RPT_TARGET_ID', 'RPT_FLAGGED_AT'],
        ] as $table => $columns) {
            Schema::create($table, function (Blueprint $blueprint) use ($columns) {
                foreach ($columns as $column) {
                    $blueprint->string($column)->nullable();
                }
            });
        }
        Schema::create('personal_access_tokens', function (Blueprint $table) {
            $table->id();
            $table->string('tokenable_type');
            $table->string('tokenable_id');
            $table->string('name');
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();
        });
    }

    private function account(string $id = 'CHK001', bool $seller = false): User
    {
        $user = User::create([
            'USR_ID' => $id, 'USR_NAME' => 'Synthetic '.$id,
            'USR_EMAIL' => strtolower($id).'@example.test', 'USR_PASSWORD' => Hash::make('check-password'),
            'USR_MOBILE_NUMBER' => '09123456789', 'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE',
        ]);
        DB::table('buyer')->insert(['BUY_ID' => 'B'.$id, 'USR_ID' => $id]);
        if ($seller) {
            DB::table('farmer')->insert(['FMR_ID' => 'F'.$id, 'BUY_ID' => 'B'.$id, 'FMR_SELLER_MODE_ACTIVE' => 1]);
        }
        return $user;
    }

    private function listing(string $owner = 'CHK001'): void
    {
        DB::table('farm')->insert(['FRM_ID' => 'FARM01', 'FMR_ID' => 'F'.$owner, 'FRM_NAME' => 'Dummy farm', 'FRM_STATUS' => 'APPROVED', 'FRM_PIN_ACTIVE' => 1]);
        DB::table('crop_category')->insert(['CAT_ID' => 'CAT001', 'CAT_NAME' => 'Vegetables']);
        DB::table('listing')->insert(['LST_ID' => 'LIST01', 'FMR_ID' => 'F'.$owner, 'FRM_ID' => 'FARM01', 'CAT_ID' => 'CAT001', 'LST_CROP_ICON' => 'Tomato', 'LST_STATUS' => 'AVAILABLE_NOW', 'LST_AVAILABILITY' => 'ACTIVE', 'LST_CREATED_AT' => now(), 'LST_EXPIRY_DATE' => now()->addDay()]);
    }

    public function test_01_guest_web_and_api_access_is_denied(): void
    {
        foreach (['/dashboard', '/profile', '/seller-requests'] as $uri) {
            $this->get($uri)->assertRedirect('/login');
        }
        foreach (['/api/user', '/api/farms', '/api/my-listings', '/api/admin/seller-requests', '/api/conversations'] as $uri) {
            $this->getJson($uri)->assertUnauthorized();
        }
        $this->postJson('/api/listings', [])->assertUnauthorized();
    }

    public function test_02_and_04_buyer_and_farmer_cannot_use_admin_pages_or_seller_decisions(): void
    {
        DB::table('farm')->insert(['FRM_ID' => 'FARM01', 'FMR_ID' => 'TARGET', 'FRM_STATUS' => 'PENDING_REVIEW', 'FRM_PIN_ACTIVE' => 0]);
        foreach ([false, true] as $seller) {
            $user = $this->account($seller ? 'FARMER' : 'BUYER', $seller);
            $this->actingAs($user);
            foreach (['/dashboard', '/users', '/reports', '/seller-requests'] as $uri) {
                $this->get($uri)->assertForbidden();
            }
            foreach (['approve', 'reject'] as $action) {
                $this->postJson('/api/admin/seller-requests/FARM01/'.$action, [])->assertForbidden();
                $this->post('/seller-requests/FARM01/'.$action, [])->assertForbidden();
            }
        }
        $this->assertSame(1, DB::table('farm')->count());
        $this->assertSame('PENDING_REVIEW', DB::table('farm')->value('FRM_STATUS'));
        $this->assertSame('0', DB::table('farm')->value('FRM_PIN_ACTIVE'));
    }

    public function test_03_other_farmer_listing_edit_delete_and_photo_actions_are_denied(): void
    {
        $this->account('OWNER1', true);
        $other = $this->account('OTHER1', true);
        $this->listing('OWNER1');
        $this->actingAs($other);
        $this->patchJson('/api/listings/LIST01', ['crop_icon' => 'Changed'])->assertForbidden();
        $this->deleteJson('/api/listings/LIST01')->assertForbidden();
        $this->postJson('/api/listings/LIST01/photos', [])->assertForbidden();
        $this->assertSame('Tomato', DB::table('listing')->value('LST_CROP_ICON'));
        $this->assertSame(1, DB::table('listing')->count());
    }

    public function test_05_protected_profile_fields_cannot_be_mass_assigned(): void
    {
        $user = $this->account();
        $this->actingAs($user)->patchJson('/api/user', [
            'name' => 'Allowed name', 'USR_ROLE' => 'ADMIN', 'role' => 'ADMIN',
            'is_admin' => 1, 'owner_id' => 'OTHER', 'approval_status' => 'APPROVED', 'USR_STATUS' => 'DEACTIVATED',
        ])->assertOk();
        $this->assertSame('GENERAL_USER', $user->fresh()->USR_ROLE);
        $this->assertSame('ACTIVE', $user->fresh()->USR_STATUS);
        $this->assertSame('Allowed name', $user->fresh()->USR_NAME);
    }

    public function test_05_protected_listing_fields_cannot_be_mass_assigned(): void
    {
        $user = $this->account('CHK001', true);
        $this->listing();
        $this->actingAs($user)->patchJson('/api/listings/LIST01', [
            'category_id' => 'CAT001', 'FMR_ID' => 'OTHER', 'FRM_ID' => 'OTHER',
            'owner_id' => 'OTHER', 'approval_status' => 'APPROVED', 'LST_AVAILABILITY' => 'REMOVED',
        ])->assertOk();
        $row = DB::table('listing')->first();
        $this->assertSame('FCHK001', $row->FMR_ID);
        $this->assertSame('FARM01', $row->FRM_ID);
        $this->assertSame('ACTIVE', $row->LST_AVAILABILITY);
    }

    public function test_06_invalid_listing_inputs_are_rejected(): void
    {
        $user = $this->account('CHK001', true);
        $this->listing();
        $this->actingAs($user);
        foreach ([['crop_icon' => str_repeat('x', 10000)], ['status' => 'INVALID'], ['harvest_date' => 'not-a-date'], ['description' => str_repeat('x', 20000)]] as $payload) {
            $this->patchJson('/api/listings/LIST01', $payload)->assertUnprocessable();
        }
        $this->postJson('/api/listings', [])->assertUnprocessable();
        $this->assertSame('Tomato', DB::table('listing')->value('LST_CROP_ICON'));
    }

    public function test_07_sql_like_search_and_filter_inputs_do_not_change_query_meaning(): void
    {
        $this->account('CHK001', true);
        $this->listing();
        $this->getJson('/api/listings?'.http_build_query(['search' => "' OR 1=1 --"]))->assertOk()->assertJsonCount(0, 'listings');
        $this->getJson('/api/listings?'.http_build_query(['category' => "' OR 1=1 --", 'sort' => 'latest; DROP TABLE listing;--']))->assertOk()->assertJsonCount(0, 'listings');
        $this->assertSame(1, DB::table('listing')->count());
    }

    public function test_08_csrf_is_rejected_with_test_bypass_disabled(): void
    {
        $this->app->bind(ValidateCsrfToken::class, fn ($app) => new class($app, $app['encrypter']) extends ValidateCsrfToken {
            protected function runningUnitTests() { return false; }
        });
        $admin = $this->account();
        $admin->update(['USR_ROLE' => 'ADMIN']);
        $this->actingAs($admin)->patch('/profile', ['name' => 'Changed'])->assertStatus(419);
        $this->actingAs($admin)->withSession(['_token' => 'known-test-token'])
            ->patch('/profile', ['_token' => 'wrong-token', 'name' => 'Changed'])->assertStatus(419);
    }

    public function test_09_api_logout_revokes_bearer_and_replay_is_denied(): void
    {
        $user = $this->account();
        $token = $user->createToken('check')->plainTextToken;
        $this->withToken($token)->getJson('/api/user')->assertOk();
        Auth::forgetGuards();
        $this->withToken($token)->postJson('/api/logout')->assertOk();
        $this->assertSame(0, DB::table('personal_access_tokens')->count());
        Auth::forgetGuards();
        $this->withToken($token)->getJson('/api/user')->assertUnauthorized();
    }

    public function test_10_password_hashing_and_generic_failure(): void
    {
        $user = $this->account();
        $this->assertNotSame('check-password', $user->USR_PASSWORD);
        $this->assertTrue(Hash::check('check-password', $user->USR_PASSWORD));
        $known = $this->postJson('/api/login', ['email' => $user->USR_EMAIL, 'password' => 'wrong'])->assertUnauthorized()->json();
        $unknown = $this->postJson('/api/login', ['email' => 'missing@example.test', 'password' => 'wrong'])->assertUnauthorized()->json();
        $this->assertSame($known, $unknown);
        $this->assertArrayNotHasKey('USR_PASSWORD', $user->toArray());
    }

    public function test_14_invalid_and_oversize_listing_images_are_rejected(): void
    {
        $user = $this->account('CHK001', true);
        $this->listing();
        $this->actingAs($user);
        $this->postJson('/api/listings/LIST01/photos', ['photos' => [UploadedFile::fake()->create('bad.txt', 1, 'text/plain')]])->assertUnprocessable();
        $png = base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jM1sAAAAASUVORK5CYII=');
        $this->postJson('/api/listings/LIST01/photos', ['photos' => [UploadedFile::fake()->createWithContent('big.png', $png)->size(5121)]])->assertUnprocessable();
        $this->assertSame(0, DB::table('listing_photo')->count());
        $disk = \Mockery::mock();
        $disk->shouldReceive('put')->once()->andReturn(true);
        $disk->shouldReceive('url')->once()->andReturn('https://example.test/dummy.png');
        Storage::shouldReceive('disk')->with('cloudinary')->andReturn($disk);
        $this->postJson('/api/listings/LIST01/photos', ['photos' => [UploadedFile::fake()->createWithContent('valid.png', $png)]])->assertCreated();
        $this->assertSame(1, DB::table('listing_photo')->count());
    }

    public function test_09_web_logout_destroys_old_session(): void
    {
        $admin = $this->account();
        $admin->update(['USR_ROLE' => 'ADMIN']);
        Auth::guard('web')->login($admin);
        $session = app('session')->driver();
        $session->start();
        $session->put('private_marker', 'synthetic-data');
        $session->save();
        $oldId = $session->getId();
        $request = \Illuminate\Http\Request::create('/logout', 'POST');
        $request->setLaravelSession($session);
        app(\App\Http\Controllers\Auth\AuthenticatedSessionController::class)->destroy($request);
        $this->assertNotSame($oldId, $session->getId());
        $this->assertEmpty($session->getHandler()->read($oldId));
        $this->assertFalse(Auth::guard('web')->check());
    }

    public function test_16_repeat_review_updates_instead_of_adding_duplicate(): void
    {
        $this->account('OWNER1', true);
        $this->listing('OWNER1');
        $reviewer = $this->account('BUYER1');
        $this->actingAs($reviewer)->postJson('/api/listings/LIST01/reviews', ['rating' => 4])->assertCreated();
        $this->postJson('/api/listings/LIST01/reviews', ['rating' => 2])->assertOk();
        $this->assertSame(1, DB::table('listing_review')->count());
        $this->assertSame('2', DB::table('listing_review')->value('LRV_RATING'));
    }

    public function test_16_fourth_farm_and_self_review_are_denied_and_report_threshold_is_ten(): void
    {
        $user = $this->account('CHK001', true);
        $this->listing();
        foreach (['FARM02', 'FARM03'] as $id) {
            DB::table('farm')->insert(['FRM_ID' => $id, 'FMR_ID' => 'FCHK001', 'FRM_STATUS' => 'PENDING_REVIEW']);
        }
        $this->actingAs($user)->postJson('/api/farms', [])->assertForbidden();
        $this->assertSame(3, DB::table('farm')->count());
        $this->postJson('/api/listings/LIST01/reviews', ['rating' => 5])->assertForbidden();
        $service = app(MassReportService::class);
        $this->assertSame(10, $service->threshold());
        for ($i = 1; $i <= 10; $i++) {
            $report = Report::create(['RPT_ID' => 'R'.$i, 'USR_ID' => 'U'.$i, 'LST_ID' => 'LIST01', 'RPT_TARGET_TYPE' => 'LISTING', 'RPT_TARGET_ID' => 'LIST01', 'RPT_STATUS' => 'New']);
            $this->assertSame($i === 10, $service->flagIfThresholdReached($report));
        }
        $this->assertSame(10, DB::table('report')->whereNotNull('RPT_FLAGGED_AT')->count());
    }
}
