<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\UserNotification;
use App\Notifications\PasswordResetCodeSent;
use App\Notifications\PremiumExpiryNotice;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;
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
            $t->string('USR_EMAIL')->nullable();
            $t->string('USR_NAME')->nullable();
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
        Notification::fake();
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
        DB::table('user')->whereIn('USR_ID', ['DUE001', 'END001', 'FAR001', 'OFF001', 'NON001'])
            ->update(['USR_EMAIL' => 'customer@example.test']);
        $this->artisan('premium:notify-expiry')->assertSuccessful();
        $this->artisan('premium:notify-expiry')->assertSuccessful();
        $this->assertSame(2, UserNotification::count());
        Http::assertSentCount(2);
        Notification::assertCount(2);
        $due = User::findOrFail('DUE001');
        Notification::assertSentTo($due, PremiumExpiryNotice::class, function ($notice, $channels) use ($due) {
            $mail = $notice->toMail($due);
            $resetMail = (new PasswordResetCodeSent($due, '123456', 10))->toMail($due);

            return $channels === ['mail']
                && $mail->from === $resetMail->from
                && $mail->subject === 'FarmSpot: Premium expires soon';
        });
        Notification::assertSentTo(User::findOrFail('END001'), PremiumExpiryNotice::class,
            fn ($notice) => $notice->title === 'Your Premium has expired');
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
        Notification::assertSentToTimes($due, PremiumExpiryNotice::class, 3);
    }
}
