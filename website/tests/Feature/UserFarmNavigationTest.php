<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\AdminMfa;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class UserFarmNavigationTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'navigation_test',
            'database.connections.navigation_test' => ['driver' => 'sqlite', 'database' => ':memory:'], 'cache.default' => 'array']);
        DB::purge('navigation_test');
        foreach ([
            'user' => ['USR_ID', 'USR_NAME', 'USR_EMAIL', 'USR_PASSWORD', 'USR_ROLE', 'USR_STATUS', 'USR_IS_SELLER'],
            'buyer' => ['BUY_ID', 'USR_ID'], 'farmer' => ['FMR_ID', 'BUY_ID', 'FMR_SELLER_MODE_ACTIVE'],
            'farm' => ['FRM_ID', 'FMR_ID', 'FRM_NAME', 'FRM_BARANGAY', 'FRM_STATUS', 'FRM_CREATED_AT'],
            'farm_photo' => ['FPHOTO_ID', 'FRM_ID', 'FPHOTO_FILE_PATH', 'FPHOTO_UPLOADED_AT'],
        ] as $table => $columns) {
            Schema::create($table, function (Blueprint $t) use ($columns) {
                foreach ($columns as $column) $t->string($column)->nullable();
                $t->primary($columns[0]);
            });
        }
        $admin = User::create(['USR_ID' => 'ADMIN1', 'USR_NAME' => 'Admin', 'USR_EMAIL' => 'admin@example.test',
            'USR_PASSWORD' => bcrypt('password'), 'USR_ROLE' => 'ADMIN', 'USR_STATUS' => 'ACTIVE']);
        $this->actingAs($admin)->withSession(['admin_mfa' => [
            'verified' => app(AdminMfa::class)->fingerprint($admin), 'started' => now()->timestamp, 'last_seen' => now()->timestamp,
        ]]);
        User::create(['USR_ID' => 'OWNER1', 'USR_NAME' => 'Farm Owner', 'USR_EMAIL' => 'owner@example.test',
            'USR_PASSWORD' => bcrypt('password'), 'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE', 'USR_IS_SELLER' => 1]);
        DB::table('buyer')->insert(['BUY_ID' => 'BUY001', 'USR_ID' => 'OWNER1']);
        DB::table('farmer')->insert(['FMR_ID' => 'FMR001', 'BUY_ID' => 'BUY001', 'FMR_SELLER_MODE_ACTIVE' => 1]);
        DB::table('farm')->insert(['FRM_ID' => 'FRM001', 'FMR_ID' => 'FMR001', 'FRM_NAME' => 'Owner Farm',
            'FRM_STATUS' => 'APPROVED', 'FRM_BARANGAY' => 'Pusok', 'FRM_CREATED_AT' => now()->toDateTimeString()]);
    }

    public function test_user_page_links_to_its_own_farm_details_route(): void
    {
        $this->get('/users/OWNER1')->assertOk()
            ->assertSee(route('users.farms.show', ['id' => 'OWNER1', 'farmId' => 'FRM001']), false)
            ->assertDontSee(route('seller-requests.show', 'FRM001'), false);
    }

    public function test_farm_opened_from_user_returns_to_that_user(): void
    {
        $this->get('/users/OWNER1/farms/FRM001')->assertOk()->assertSee('Farm Details')
            ->assertSee('Back to User Profile')->assertSee('href="'.route('users.show', 'OWNER1').'"', false)
            ->assertDontSee('Back to Seller Requests');
    }

    public function test_seller_request_navigation_stays_in_the_review_flow(): void
    {
        $this->get('/seller-requests/FRM001')->assertOk()->assertSee('Seller Request Details')
            ->assertSee('Back to Seller Requests')->assertDontSee('Back to User Profile');
    }

    public function test_farm_must_belong_to_the_user_in_the_route(): void
    {
        $this->get('/users/ADMIN1/farms/FRM001')->assertNotFound();
        $this->get('/users/OWNER1/farms/MISS01')->assertNotFound();
    }

    public function test_non_admin_cannot_open_admin_farm_details(): void
    {
        $this->actingAs(User::findOrFail('OWNER1'))->get('/users/OWNER1/farms/FRM001')->assertForbidden();
    }
}
