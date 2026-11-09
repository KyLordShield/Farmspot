<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\UserNotification;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class PremiumExpiryTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:', 'services.onesignal.app_id' => null]);
        DB::purge('sqlite');
        Schema::create('user', function (Blueprint $t) {
            $t->string('USR_ID')->primary();
            $t->string('USR_STATUS');
            $t->dateTime('USR_PREMIUM_EXPIRES_AT')->nullable();
            $t->timestamps();
        });
        Schema::create('notification', function (Blueprint $t) {
            $t->string('NOTIF_ID')->primary();
            $t->string('NOTIF_DEDUP_KEY', 80)->nullable()->unique();
            $t->string('USR_ID');
            $t->string('NOTIF_TYPE');
            $t->string('NOTIF_TITLE');
            $t->string('NOTIF_BODY');
            $t->string('NOTIF_REF_ID')->nullable();
            $t->boolean('NOTIF_IS_READ');
            $t->dateTime('NOTIF_CREATED_AT');
        });
        $this->travelTo(now()->startOfSecond());
    }

    public function test_expiry_boundaries_duplicates_and_renewal(): void
    {
        config(['services.onesignal.app_id' => 'test', 'services.onesignal.rest_api_key' => 'test', 'services.onesignal.base_url' => 'https://push.test']);
        Http::preventStrayRequests();
        Http::fake(['https://push.test/*' => Http::response(['id' => 'accepted'], 200)]);
        DB::table('user')->insert([
            ['USR_ID' => 'DUE001', 'USR_STATUS' => 'ACTIVE', 'USR_PREMIUM_EXPIRES_AT' => now()->addDay()],
            ['USR_ID' => 'END001', 'USR_STATUS' => 'ACTIVE', 'USR_PREMIUM_EXPIRES_AT' => now()],
            ['USR_ID' => 'FAR001', 'USR_STATUS' => 'ACTIVE', 'USR_PREMIUM_EXPIRES_AT' => now()->addDay()->addSecond()],
            ['USR_ID' => 'OFF001', 'USR_STATUS' => 'SUSPENDED', 'USR_PREMIUM_EXPIRES_AT' => now()],
            ['USR_ID' => 'NON001', 'USR_STATUS' => 'ACTIVE', 'USR_PREMIUM_EXPIRES_AT' => null],
        ]);
        $this->artisan('premium:notify-expiry')->assertSuccessful();
        $this->artisan('premium:notify-expiry')->assertSuccessful();
        $this->assertSame(2, UserNotification::count());
        Http::assertSentCount(2);
        $this->assertDatabaseHas('notification', ['USR_ID' => 'DUE001', 'NOTIF_TYPE' => 'PREMIUM_EXPIRING_SOON']);
        $this->assertDatabaseHas('notification', ['USR_ID' => 'END001', 'NOTIF_TYPE' => 'PREMIUM_EXPIRED']);

        $this->travel(1)->days();
        $this->artisan('premium:notify-expiry')->assertSuccessful();
        $this->assertDatabaseHas('notification', ['USR_ID' => 'DUE001', 'NOTIF_TYPE' => 'PREMIUM_EXPIRED']);

        DB::table('user')->where('USR_ID', 'DUE001')->update(['USR_PREMIUM_EXPIRES_AT' => now()->addMonth()]);
        $before = UserNotification::where('USR_ID', 'DUE001')->count();
        $this->artisan('premium:notify-expiry')->assertSuccessful();
        $this->assertSame($before, UserNotification::where('USR_ID', 'DUE001')->count());
        $this->travelTo(User::find('DUE001')->USR_PREMIUM_EXPIRES_AT->copy()->subHours(12));
        $this->artisan('premium:notify-expiry')->assertSuccessful();
        $this->assertSame(2, UserNotification::where('USR_ID', 'DUE001')->where('NOTIF_TYPE', 'PREMIUM_EXPIRING_SOON')->count());
    }
}
