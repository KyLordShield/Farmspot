<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * A token that outlives a deactivation must not grant access.
 *
 * Deactivation revokes tokens, and login checks USR_STATUS, so the honest way
 * an account gets locked out is already covered elsewhere. This guards the
 * belt-and-braces layer: a token that somehow survived — minted in the same
 * second as the deactivation, restored from a backup, or left behind by a code
 * path that forgot to revoke — is refused on the next request instead of being
 * honoured until the person chooses to sign out.
 */
class InactiveAccountMiddlewareTest extends TestCase
{
    use RefreshDatabase;

    private function makeUser(string $status = 'ACTIVE', array $overrides = []): User
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table('user')->where('USR_ID', $id)->exists());

        return User::create(array_merge([
            'USR_ID' => $id,
            'USR_NAME' => 'Person '.$id,
            'USR_EMAIL' => strtolower($id).'@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '09'.random_int(10000000, 99999999),
            'USR_ROLE' => 'GENERAL_USER',
            'USR_IS_SELLER' => 0,
            'USR_STATUS' => $status,
            'USR_CREATED_AT' => now(),
        ], $overrides));
    }

    /**
     * Make a request carrying only a bearer token, with no lingering web
     * session that Sanctum's guard would prefer over it.
     */
    private function requestWithToken(string $token): TestResponse
    {
        $this->flushSession();
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/conversations');
    }

    public function test_an_active_account_is_allowed_through()
    {
        $user = $this->makeUser('ACTIVE');
        $token = $user->createToken('their phone')->plainTextToken;

        $this->requestWithToken($token)->assertOk();
    }

    public function test_a_surviving_token_on_a_taken_down_account_is_refused_and_killed()
    {
        $user = $this->makeUser('DEACTIVATED', [
            'USR_TAKEDOWN_REASON' => 'Repeated fake listings',
        ]);
        $token = $user->createToken('their phone')->plainTextToken;

        $this->requestWithToken($token)
            ->assertStatus(403)
            ->assertJsonPath('code', 'ACCOUNT_TAKEN_DOWN')
            ->assertJsonPath('reason', 'Repeated fake listings');

        // The token that got in must not survive the refusal.
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_a_surviving_token_on_a_plainly_deactivated_account_gets_no_appeal_code()
    {
        $user = $this->makeUser('DEACTIVATED');
        $token = $user->createToken('their phone')->plainTextToken;

        $response = $this->requestWithToken($token)->assertStatus(403);

        $response->assertJsonPath('code', 'ACCOUNT_DEACTIVATED');
        $this->assertArrayNotHasKey('reason', $response->json());
    }

    public function test_a_surviving_token_on_a_pending_account_is_refused()
    {
        $user = $this->makeUser('PENDING_VERIFICATION');
        $token = $user->createToken('their phone')->plainTextToken;

        $this->requestWithToken($token)
            ->assertStatus(403)
            ->assertJsonPath('code', 'ACCOUNT_PENDING_VERIFICATION');
    }
}
