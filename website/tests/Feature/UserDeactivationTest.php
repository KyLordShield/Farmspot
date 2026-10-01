<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Deactivating a user has to end their access, not just their next login.
 *
 * The app authenticates with Sanctum tokens. Setting USR_STATUS = DEACTIVATED
 * is checked once, in AuthController, at login — nothing else looks at it. So a
 * user deactivated from the admin panel while the app was installed on their
 * phone kept working: their existing token never expires on its own and no
 * request re-reads the status. Revoking the tokens is what makes the button
 * mean what it says.
 *
 * The same revocation exists on the report action, which is the path most
 * deactivations actually arrive through.
 */
class UserDeactivationTest extends TestCase
{
    use RefreshDatabase;

    private function id(string $prefix): string
    {
        do {
            $id = strtoupper(Str::random(6));
        } while (DB::table($prefix === 'USR' ? 'user' : 'buyer')->where($prefix.'_ID', $id)->exists());

        return $id;
    }

    private function makeUser(string $role = 'GENERAL_USER'): User
    {
        $id = $this->id('USR');

        return User::create([
            'USR_ID' => $id,
            'USR_NAME' => 'Person '.$id,
            'USR_EMAIL' => strtolower($id).'@test.local',
            'USR_PASSWORD' => bcrypt('password123'),
            'USR_MOBILE_NUMBER' => '09'.random_int(10000000, 99999999),
            'USR_ROLE' => $role,
            'USR_IS_SELLER' => 0,
            'USR_STATUS' => 'ACTIVE',
            'USR_CREATED_AT' => now(),
        ]);
    }

    /** The payload the admin edit form posts back. */
    private function formFor(User $user, array $overrides = []): array
    {
        return array_merge([
            'USR_NAME' => $user->USR_NAME,
            'USR_EMAIL' => $user->USR_EMAIL,
            'USR_MOBILE_NUMBER' => $user->USR_MOBILE_NUMBER,
            'USR_ROLE' => $user->USR_ROLE,
            'USR_STATUS' => $user->USR_STATUS,
        ], $overrides);
    }

    /**
     * Make a request carrying only a bearer token.
     *
     * The deactivation above was performed with actingAs($admin), which leaves a
     * web session active for the rest of the test. Sanctum's guard checks that
     * session before the bearer token, so without clearing it the request below
     * would be answered as the admin — who is very much still signed in — and
     * would return 200 whether or not the target's token had been revoked.
     */
    private function requestWithToken(string $token): TestResponse
    {
        $this->flushSession();
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/conversations');
    }

    public function test_deactivating_through_the_edit_form_revokes_that_users_tokens()
    {
        $admin = $this->makeUser('ADMIN');
        $target = $this->makeUser();

        $target->createToken('their phone');
        $this->assertDatabaseCount('personal_access_tokens', 1);

        $this->actingAs($admin)
            ->put("/users/{$target->USR_ID}", $this->formFor($target, ['USR_STATUS' => 'DEACTIVATED']))
            ->assertRedirect(route('users'));

        $this->assertSame('DEACTIVATED', $target->fresh()->USR_STATUS);
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_the_deactivate_button_revokes_that_users_tokens()
    {
        $admin = $this->makeUser('ADMIN');
        $target = $this->makeUser();

        $target->createToken('their phone');
        $target->createToken('their tablet');
        $this->assertDatabaseCount('personal_access_tokens', 2);

        $this->actingAs($admin)
            ->delete("/users/{$target->USR_ID}")
            ->assertRedirect(route('users'));

        $this->assertSame('DEACTIVATED', $target->fresh()->USR_STATUS);
        // Every device, not just the most recent one.
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_the_token_is_unusable_immediately_rather_than_at_the_next_login()
    {
        // The token itself is what has to stop working. A deactivated user who
        // was already signed in should get a 401 from the very next request.
        $admin = $this->makeUser('ADMIN');
        $target = $this->makeUser();

        $token = $target->createToken('their phone')->plainTextToken;

        $this->actingAs($admin)
            ->put("/users/{$target->USR_ID}", $this->formFor($target, ['USR_STATUS' => 'DEACTIVATED']))
            ->assertRedirect(route('users'));

$this->requestWithToken($token)->assertUnauthorized();
    }

    public function test_reactivating_an_account_does_not_hand_back_the_old_tokens()
    {
        // Tokens are revoked, not frozen. Reinstating the account means the
        // person signs in again and gets a fresh token, rather than an old one
        // quietly becoming valid again.
        $admin = $this->makeUser('ADMIN');
        $target = $this->makeUser();

        $token = $target->createToken('their phone')->plainTextToken;

        $this->actingAs($admin)
            ->put("/users/{$target->USR_ID}", $this->formFor($target, ['USR_STATUS' => 'DEACTIVATED']));

        $this->actingAs($admin)
            ->put("/users/{$target->USR_ID}", $this->formFor($target->fresh(), ['USR_STATUS' => 'ACTIVE']))
            ->assertRedirect(route('users'));

        $this->assertSame('ACTIVE', $target->fresh()->USR_STATUS);
$this->assertDatabaseCount('personal_access_tokens', 0);

        $this->requestWithToken($token)->assertUnauthorized();
    }

    public function test_editing_an_account_without_deactivating_it_leaves_tokens_alone()
    {
        // Only a transition to DEACTIVATED should sign the person out. A
        // moderator correcting a typo in a name must not log them out of their
        // phone.
        $admin = $this->makeUser('ADMIN');
        $target = $this->makeUser();

        $target->createToken('their phone');

        $this->actingAs($admin)
            ->put("/users/{$target->USR_ID}", $this->formFor($target, ['USR_NAME' => 'Corrected Name']))
            ->assertRedirect(route('users'));

        $this->assertSame('Corrected Name', $target->fresh()->USR_NAME);
        $this->assertDatabaseCount('personal_access_tokens', 1);
    }

    public function test_a_non_admin_cannot_deactivate_anybody()
    {
        // /users sits behind auth + admin. Without that a buyer could sign in to
        // the web panel and deactivate a competitor, or an admin outright.
        $nosy = $this->makeUser();
        $target = $this->makeUser();

        $target->createToken('their phone');

        $this->actingAs($nosy)
            ->put("/users/{$target->USR_ID}", $this->formFor($target, ['USR_STATUS' => 'DEACTIVATED']))
            ->assertForbidden();

        $this->actingAs($nosy)
            ->delete("/users/{$target->USR_ID}")
            ->assertForbidden();

        $this->assertSame('ACTIVE', $target->fresh()->USR_STATUS);
        $this->assertDatabaseCount('personal_access_tokens', 1);
    }
}

