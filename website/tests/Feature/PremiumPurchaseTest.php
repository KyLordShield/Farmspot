<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PremiumPurchaseTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        // Isolated minimal schema: never refresh or truncate the real database.
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:', 'premium.simulation_enabled' => true]);
        DB::purge('sqlite');
        Schema::create('user', function (Blueprint $table) {
            $table->string('USR_ID')->primary();
            $table->string('USR_NAME');
            $table->string('USR_EMAIL')->unique();
            $table->string('USR_PASSWORD');
            $table->string('USR_STATUS');
            $table->string('USR_ROLE');
            $table->boolean('USR_IS_SELLER')->default(false);
        });
        (require database_path('migrations/2026_10_24_000001_add_premium_access_to_user_table.php'))->up();
    }

    private function account(string $id = 'BUY001', bool $seller = false): User
    {
        return User::create([
            'USR_ID' => $id, 'USR_NAME' => 'Premium Test',
            'USR_EMAIL' => $id.'@example.test', 'USR_PASSWORD' => bcrypt('password'),
            'USR_STATUS' => 'ACTIVE', 'USR_ROLE' => 'GENERAL_USER', 'USR_IS_SELLER' => $seller,
        ]);
    }

    public function test_purchase_is_persisted_for_only_the_authenticated_account(): void
    {
        $this->travelTo(now()->setDate(2026, 1, 31)->startOfDay());
        $buyer = $this->account();
        $other = $this->account('BUY002');
        Sanctum::actingAs($buyer);
        $this->postJson('/api/premium/simulate-purchase', ['USR_ID' => $other->USR_ID, 'expires_at' => '2099-01-01'])
            ->assertOk()->assertJsonPath('simulated', true)->assertJsonPath('user.USR_IS_PREMIUM', true);
        $this->assertSame('2026-02-28', $buyer->fresh()->USR_PREMIUM_EXPIRES_AT->toDateString());
        $this->assertFalse($other->fresh()->USR_IS_PREMIUM);
        Sanctum::actingAs($buyer->fresh());
        $this->getJson('/api/user')->assertOk()->assertJsonPath('USR_IS_PREMIUM', true);
        $this->travelBack();
    }

    public function test_retry_does_not_extend_an_active_subscription(): void
    {
        $user = $this->account();
        Sanctum::actingAs($user);
        $this->postJson('/api/premium/simulate-purchase')->assertOk();
        $expiry = $user->fresh()->USR_PREMIUM_EXPIRES_AT->toISOString();
        $this->travel(1)->days();
        $this->postJson('/api/premium/simulate-purchase')->assertOk();
        $this->assertSame($expiry, $user->fresh()->USR_PREMIUM_EXPIRES_AT->toISOString());
        $this->travelBack();
    }

    public function test_expired_plan_is_not_premium_and_can_be_purchased_again(): void
    {
        $user = $this->account();
        $user->USR_PREMIUM_EXPIRES_AT = now()->subDay();
        $user->save();
        Sanctum::actingAs($user->fresh());
        $this->getJson('/api/user')->assertJsonPath('USR_IS_PREMIUM', false);
        $this->postJson('/api/premium/simulate-purchase')->assertOk()->assertJsonPath('user.USR_IS_PREMIUM', true);
    }

    public function test_sellers_can_purchase_without_changing_seller_status(): void
    {
        Sanctum::actingAs($this->account(seller: true));
        $this->postJson('/api/premium/simulate-purchase')->assertOk()
            ->assertJsonPath('user.USR_IS_PREMIUM', true)->assertJsonPath('user.USR_IS_SELLER', 1);
    }

    public function test_simulation_can_be_disabled_without_granting_access(): void
    {
        $user = $this->account();
        Sanctum::actingAs($user);
        config(['premium.simulation_enabled' => false]);
        $this->postJson('/api/premium/simulate-purchase')->assertForbidden();
        $this->assertFalse($user->fresh()->USR_IS_PREMIUM);
    }

    public function test_profile_updates_cannot_grant_premium(): void
    {
        $user = $this->account();
        Sanctum::actingAs($user);
        $this->patchJson('/api/user', ['USR_IS_PREMIUM' => true, 'USR_PREMIUM_EXPIRES_AT' => '2099-01-01'])
            ->assertOk()->assertJsonPath('user.USR_IS_PREMIUM', false);
        $this->assertNull($user->fresh()->USR_PREMIUM_EXPIRES_AT);
    }

    public function test_anonymous_and_deactivated_accounts_cannot_purchase(): void
    {
        $this->postJson('/api/premium/simulate-purchase')->assertUnauthorized();
        $user = $this->account();
        $user->USR_STATUS = 'DEACTIVATED';
        $user->save();
        Sanctum::actingAs($user);
        $this->postJson('/api/premium/simulate-purchase')->assertForbidden();
        $this->assertFalse($user->fresh()->USR_IS_PREMIUM);
    }
}
