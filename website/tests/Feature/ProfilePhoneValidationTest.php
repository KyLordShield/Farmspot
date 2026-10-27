<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\MobileNumber;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class ProfilePhoneValidationTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:']);
        DB::purge('sqlite');
        Schema::create('user', function (Blueprint $table) {
            $table->string('USR_ID')->primary();
            $table->string('USR_NAME');
            $table->string('USR_EMAIL')->unique();
            $table->string('USR_PASSWORD');
            $table->string('USR_MOBILE_NUMBER')->unique();
            $table->string('USR_ADDRESS')->nullable();
            $table->string('USR_STATUS');
            $table->string('USR_ROLE');
            $table->boolean('USR_IS_SELLER')->default(false);
            $table->dateTime('USR_CREATED_AT')->nullable();
        });
    }

    private function account(string $id, string $phone): User
    {
        return User::create(['USR_ID' => $id, 'USR_NAME' => 'Test Person', 'USR_EMAIL' => $id.'@example.test',
            'USR_PASSWORD' => bcrypt('example123'), 'USR_MOBILE_NUMBER' => $phone,
            'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE', 'USR_CREATED_AT' => now()]);
    }

    public function test_profile_rejects_invalid_phone_formats_with_registration_wording(): void
    {
        $user = $this->account('USR001', '09171234567');
        $this->actingAs($user, 'sanctum');
        foreach (['08171234567', '091712345678', '0917123456', '+639171234567', '09abcdefghi'] as $phone) {
            $this->patchJson('/api/user', ['mobile_number' => $phone])->assertUnprocessable()
                ->assertJsonPath('errors.mobile_number.0', MobileNumber::INVALID);
        }
        $this->patchJson('/api/user', ['mobile_number' => ''])->assertUnprocessable()
            ->assertJsonPath('errors.mobile_number.0', MobileNumber::REQUIRED);
        $this->assertSame('09171234567', $user->fresh()->USR_MOBILE_NUMBER);
    }

    public function test_duplicate_number_is_rejected_but_keeping_own_number_and_changing_to_unused_number_work(): void
    {
        $user = $this->account('USR001', '09171234567');
        $this->account('USR002', '09281234567');
        $this->actingAs($user, 'sanctum');
        $this->patchJson('/api/user', ['mobile_number' => '09281234567'])->assertUnprocessable()
            ->assertJsonPath('errors.mobile_number.0', MobileNumber::DUPLICATE);
        $this->patchJson('/api/user', ['mobile_number' => '09171234567'])->assertOk();
        $this->patchJson('/api/user', ['mobile_number' => '09391234567'])->assertOk();
        $this->assertSame('09391234567', $user->fresh()->USR_MOBILE_NUMBER);
    }

    public function test_email_cannot_be_changed_and_unrelated_profile_edits_still_work(): void
    {
        $user = $this->account('USR001', '09171234567');
        $this->actingAs($user, 'sanctum');
        $this->patchJson('/api/user', ['email' => 'changed@example.test'])->assertUnprocessable()->assertJsonValidationErrors('email');
        $this->patchJson('/api/user', ['USR_EMAIL' => 'changed@example.test'])->assertUnprocessable()->assertJsonValidationErrors('USR_EMAIL');
        $this->patchJson('/api/user', ['address' => 'Pusok'])->assertOk()->assertJsonPath('user.USR_EMAIL', 'USR001@example.test');
        $this->assertSame('USR001@example.test', $user->fresh()->USR_EMAIL);
    }

    public function test_registration_enforces_same_format_and_duplicate_messages(): void
    {
        $this->account('USR001', '09171234567');
        $data = ['USR_NAME' => 'New Person', 'USR_EMAIL' => 'new@example.test',
            'USR_PASSWORD' => 'example123', 'USR_PASSWORD_confirmation' => 'example123'];
        foreach (['08171234567', '091712345678', '09abcdefgh1'] as $phone) {
            $this->postJson('/api/register', [...$data, 'USR_MOBILE_NUMBER' => $phone])->assertUnprocessable()
                ->assertJsonPath('errors.USR_MOBILE_NUMBER.0', MobileNumber::INVALID);
        }
        $this->postJson('/api/register', [...$data, 'USR_MOBILE_NUMBER' => '09171234567'])->assertUnprocessable()
            ->assertJsonPath('errors.USR_MOBILE_NUMBER.0', MobileNumber::DUPLICATE);
        $this->assertDatabaseCount('user', 1);
    }
}
