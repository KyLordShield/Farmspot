<?php

namespace Tests\Feature;

use App\Http\Middleware\EnsureUserIsAdmin;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/** Observations of current weaknesses, NOT assertions that these behaviors are secure.
 * Uses a minimal, in-memory schema; never runs project migrations or external services.
 */
class SecurityAuditObservationTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'cache.default' => 'array', 'session.driver' => 'array']);
        DB::purge('sqlite');
        Schema::create('user', function (Blueprint $table) {
            $table->string('USR_ID')->primary();
            $table->string('USR_NAME');
            $table->string('USR_EMAIL')->unique();
            $table->string('USR_PASSWORD');
            $table->string('USR_MOBILE_NUMBER');
            $table->string('USR_ADDRESS')->nullable();
            $table->string('USR_ROLE');
            $table->string('USR_STATUS');
            $table->integer('USR_IS_SELLER')->default(0);
            $table->timestamp('USR_CREATED_AT')->nullable();
        });
        Schema::create('buyer', function (Blueprint $table) {
            $table->string('BUY_ID')->primary();
            $table->string('USR_ID');
        });
    }

    private function person(array $attributes = []): User
    {
        return User::create(array_merge([
            'USR_ID' => 'AUD001', 'USR_NAME' => 'Audit Person',
            'USR_EMAIL' => 'audit@example.test', 'USR_PASSWORD' => bcrypt('audit-password'),
            'USR_MOBILE_NUMBER' => '09123456789', 'USR_ADDRESS' => 'Private test address',
            'USR_ROLE' => 'GENERAL_USER', 'USR_STATUS' => 'ACTIVE',
        ], $attributes));
    }

    public function test_observation_mobile_login_accepts_twelve_failed_attempts_without_throttling(): void
    {
        $this->person();
        for ($i = 0; $i < 12; $i++) {
            $this->postJson('/api/login', ['email' => 'audit@example.test', 'password' => 'wrong'])
                ->assertStatus(401);
        }
    }

    public function test_control_reset_endpoint_throttles_same_ip(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/reset-password', [])->assertStatus(422);
        }
        $this->postJson('/api/reset-password', [])->assertStatus(429);
    }

    public function test_observation_forwarded_ip_rotation_bypasses_reset_route_limit(): void
    {
        for ($i = 1; $i <= 8; $i++) {
            $this->withHeader('X-Forwarded-For', '198.51.100.'.$i)
                ->postJson('/api/reset-password', [])->assertStatus(422);
        }
    }

    public function test_observation_guest_can_read_buyer_phone_and_address(): void
    {
        $this->person();
        $this->getJson('/api/users/AUD001/profile')->assertOk()
            ->assertJsonPath('user.phone', '09123456789')
            ->assertJsonPath('user.address', 'Private test address');
    }

    public function test_observation_deactivated_admin_passes_admin_middleware(): void
    {
        $user = $this->person(['USR_ROLE' => 'ADMIN', 'USR_STATUS' => 'DEACTIVATED']);
        $request = Request::create('/profile');
        $request->setUserResolver(fn () => $user);
        $response = (new EnsureUserIsAdmin)->handle($request, fn () => response('allowed'));
        $this->assertSame(200, $response->getStatusCode());
        $route = app('router')->getRoutes()->match(Request::create('/profile'));
        $this->assertNotContains('active', $route->gatherMiddleware());
    }

    public function test_control_general_user_cannot_open_admin_profile(): void
    {
        $this->actingAs($this->person())->get('/profile')->assertForbidden();
    }

    public function test_control_guest_cannot_read_conversations(): void
    {
        $this->getJson('/api/conversations')->assertUnauthorized();
    }

    public function test_observation_admin_password_change_reports_success_but_keeps_old_password(): void
    {
        $user = $this->person(['USR_ROLE' => 'ADMIN']);
        $this->actingAs($user)->from('/profile')->put('/password', [
            'current_password' => 'audit-password',
            'password' => 'replacement-password-123',
            'password_confirmation' => 'replacement-password-123',
        ])->assertSessionHasNoErrors()->assertSessionHas('status', 'password-updated');
        $this->assertTrue(\Illuminate\Support\Facades\Hash::check('audit-password', $user->fresh()->USR_PASSWORD));
        $this->assertFalse(\Illuminate\Support\Facades\Hash::check('replacement-password-123', $user->fresh()->USR_PASSWORD));
    }
}
