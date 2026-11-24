<?php

namespace Tests\Feature;

use App\Models\PasswordResetCode;
use App\Models\User;
use App\Notifications\PasswordResetCodeSent;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class AppPasswordResetCodeTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        // Isolated in-memory fixtures: never migrate or modify the local/live DB.
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:']);
        DB::purge('sqlite');
        Schema::create('user', function (Blueprint $t) {
            $t->string('USR_ID')->primary();
            foreach (['USR_NAME', 'USR_EMAIL', 'USR_PASSWORD', 'USR_ROLE', 'USR_STATUS'] as $column) $t->string($column);
        });
        Schema::create('password_reset_code', function (Blueprint $t) {
            $t->string('USR_ID')->primary();
            $t->string('RSTC_CODE_HASH');
            $t->dateTime('RSTC_EXPIRES_AT');
            $t->integer('RSTC_ATTEMPTS')->default(0);
            $t->dateTime('RSTC_CONSUMED_AT')->nullable();
            $t->dateTime('RSTC_CREATED_AT');
        });
        Schema::create('personal_access_tokens', function (Blueprint $t) {
            $t->id(); $t->string('tokenable_type'); $t->string('tokenable_id');
        });
        DB::table('user')->insert([
            'USR_ID' => 'RESET1', 'USR_NAME' => 'Reset Tester', 'USR_EMAIL' => 'reset@example.test',
            'USR_PASSWORD' => Hash::make('OldPassword123!'), 'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE',
        ]);
        Notification::fake();
    }

    public function test_request_stores_hashed_code_in_canonical_table_and_notifies_email(): void
    {
        // SQLite ignores table-name case, so explicitly enforce the Linux contract.
        $this->assertSame('password_reset_code', (new PasswordResetCode)->getTable());
        $response = $this->postJson('/api/forgot-password', ['email' => 'reset@example.test'])->assertOk();
        $response->assertJsonMissingPath('debug_code');
        $user = User::findOrFail('RESET1');
        $this->assertSame('reset@example.test', $user->routeNotificationForMail());
        Notification::assertSentTo($user, PasswordResetCodeSent::class, function ($notification) {
            $row = PasswordResetCode::findOrFail('RESET1');
            return Hash::check($notification->code, $row->RSTC_CODE_HASH)
                && $row->RSTC_CODE_HASH !== $notification->code
                && $row->usability() === 'usable';
        });
    }

    public function test_issued_code_resets_password_revokes_tokens_and_cannot_be_reused(): void
    {
        $this->postJson('/api/forgot-password', ['email' => 'reset@example.test'])->assertOk();
        $code = Notification::sent(User::findOrFail('RESET1'), PasswordResetCodeSent::class)->first()->code;
        DB::table('personal_access_tokens')->insert(['tokenable_type' => User::class, 'tokenable_id' => 'RESET1']);
        $payload = ['email' => 'reset@example.test', 'code' => $code, 'password' => 'NewPassword123!', 'password_confirmation' => 'NewPassword123!'];
        $this->postJson('/api/reset-password', $payload)->assertOk();
        $this->assertTrue(Hash::check('NewPassword123!', User::findOrFail('RESET1')->USR_PASSWORD));
        $this->assertSame(0, DB::table('personal_access_tokens')->count());
        $this->postJson('/api/reset-password', $payload)->assertUnprocessable();
    }

    public function test_normalization_preserves_existing_codes_and_is_repeatable(): void
    {
        $this->postJson('/api/forgot-password', ['email' => 'reset@example.test'])->assertOk();
        $before = PasswordResetCode::findOrFail('RESET1')->getAttributes();
        $migration = require database_path('migrations/2026_11_25_000001_normalize_password_reset_code_table_name.php');
        $migration->up();
        $migration->up();
        $migration->down();
        $this->assertSame($before, PasswordResetCode::findOrFail('RESET1')->getAttributes());
    }

    public function test_unknown_email_has_same_response_without_sending_notification(): void
    {
        $known = $this->postJson('/api/forgot-password', ['email' => 'reset@example.test'])->assertOk();
        Notification::fake();
        $unknown = $this->postJson('/api/forgot-password', ['email' => 'unknown@example.test'])->assertOk();
        $this->assertSame($known->json(), $unknown->json());
        Notification::assertNothingSent();
    }
}
