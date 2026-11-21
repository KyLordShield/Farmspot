<?php
namespace Tests\Feature\Auth;

use App\Models\User;
use App\Notifications\AdminPasswordResetCode;
use App\Services\AdminMfa;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class PasswordUpdateTest extends TestCase
{
    private User $admin;
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'password_test',
            'database.connections.password_test' => ['driver' => 'sqlite', 'database' => ':memory:'],
            'cache.default' => 'array', 'app.key' => 'base64:'.base64_encode(random_bytes(32)),
            'mail.default' => 'smtp', 'mail.mailers.smtp.transport' => 'smtp',
            'services.brevo.admin_mail_key' => null, 'services.brevo.admin_mail_from' => null]);
        DB::purge('password_test');
        Schema::create('user', function (Blueprint $t) {
            $t->string('USR_ID')->primary();
            foreach (['USR_NAME', 'USR_EMAIL', 'USR_PASSWORD', 'USR_ROLE', 'USR_STATUS'] as $field) $t->string($field);
            $t->string('USR_MOBILE_NUMBER')->nullable();
        });
        Notification::fake();
        Http::preventStrayRequests();
        $this->admin = User::create(['USR_ID' => 'ADMIN1', 'USR_NAME' => 'Profile Admin',
            'USR_EMAIL' => 'admin@example.test', 'USR_PASSWORD' => Hash::make('old-password'),
            'USR_ROLE' => 'ADMIN', 'USR_STATUS' => 'ACTIVE']);
        $this->verified();
    }
    private function verified(): void
    {
        $this->actingAs($this->admin, 'web')->withSession(['admin_mfa' => [
            'verified' => app(AdminMfa::class)->fingerprint($this->admin),
            'started' => now()->timestamp, 'last_seen' => now()->timestamp]]);
    }
    private function code(): string
    {
        $this->post(route('profile.password.code'))->assertRedirect(route('profile.edit'))
            ->assertSessionHas('status', 'password-code-sent');
        return Notification::sent($this->admin, AdminPasswordResetCode::class)->last()->code;
    }
    private function payload(string $code): array
    {
        return ['current_password' => 'old-password', 'code' => $code,
            'password' => 'new-secure-password', 'password_confirmation' => 'new-secure-password'];
    }
    private function verify(string $code): void
    {
        $this->post(route('profile.password.verify'), ['code' => $code])
            ->assertRedirect(route('profile.edit'))->assertSessionHas('status', 'password-email-verified');
    }
    public function test_profile_details_and_navigation_link(): void
    {
        $this->get('/profile')->assertOk()->assertSee('Profile Admin')->assertSee('admin@example.test')
            ->assertSee('Open administrator profile')->assertSee('Send verification code')
            ->assertSee('Save profile')->assertDontSee('name="current_password"', false)->assertDontSee('Delete account');
    }
    public function test_verified_reset_logs_out_and_cannot_be_replayed(): void
    {
        $code = $this->code();
        $challenge = session('admin_password');
        $this->assertNotSame($code, $challenge['hash']);
        $this->get('/profile')->assertOk()->assertSee($challenge['reference']);
        $this->get('/profile')->assertDontSee('name="current_password"', false)->assertSee('profile-code-boxes');
        $this->verify($code);
        $challenge = session('admin_password');
        $this->get('/profile')->assertOk()->assertSee('name="current_password"', false)->assertDontSee('profile-code-boxes');
        $this->put('/password', $this->payload($code))->assertRedirect(route('login'));
        $this->assertTrue(Hash::check('new-secure-password', $this->admin->refresh()->USR_PASSWORD));
        $this->assertGuest('web');
        $this->assertNull(session('admin_password'));
        $this->verified();
        $this->withSession(['admin_password' => $challenge])->put('/password', [
            'current_password' => 'new-secure-password', 'code' => $code,
            'password' => 'another-secure-password', 'password_confirmation' => 'another-secure-password',
        ])->assertSessionHasErrorsIn('updatePassword', 'code');
    }
    public function test_missing_or_incorrect_code_is_rejected_and_not_flashed(): void
    {
        $this->put('/password', $this->payload('123456'))->assertSessionHasErrorsIn('updatePassword', 'code');
        $code = $this->code();
        $this->post(route('profile.password.verify'), ['code' => $code === '000000' ? '111111' : '000000'])
            ->assertSessionHasErrorsIn('updatePassword', 'code');
        $this->assertTrue(Hash::check('old-password', $this->admin->refresh()->USR_PASSWORD));
        $this->assertNull(session('_old_input.code'));
        $this->assertNull(session('_old_input.current_password'));
        $this->assertNull(session('_old_input.password'));
    }
    public function test_current_password_and_confirmation_are_required(): void
    {
        $code = $this->code();
        $this->verify($code);
        $this->put('/password', array_replace($this->payload($code), ['current_password' => 'wrong-password']))
            ->assertSessionHasErrorsIn('updatePassword', 'current_password');
        $this->put('/password', array_replace($this->payload($code), ['password_confirmation' => 'different-password']))
            ->assertSessionHasErrorsIn('updatePassword', 'password');
        $this->put('/password', $this->payload($code))->assertRedirect(route('login'));
    }
    public function test_expired_codes_are_rejected(): void
    {
        $code = $this->code();
        $this->travel(301)->seconds();
        $this->post(route('profile.password.verify'), ['code' => $code])->assertSessionHasErrorsIn('updatePassword', 'code');
        $this->assertTrue(Hash::check('old-password', $this->admin->refresh()->USR_PASSWORD));
    }
    public function test_resend_cooldown_and_replacement(): void
    {
        $this->code();
        $first = session('admin_password.nonce');
        $this->post(route('profile.password.code'))->assertSessionHasErrorsIn('updatePassword', 'delivery');
        Notification::assertSentTimes(AdminPasswordResetCode::class, 1);
        $this->travel(61)->seconds();
        $this->code();
        $this->assertNotSame($first, session('admin_password.nonce'));
    }
    public function test_account_limits_apply_across_ip_addresses(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.'.($i + 1)])
                ->post(route('profile.password.verify'), ['code' => '123456'])->assertSessionHasErrorsIn('updatePassword', 'code');
        }
        $this->post(route('profile.password.code'))->assertSessionHasErrorsIn('updatePassword', 'delivery');
        Notification::assertNothingSent();
    }
    public function test_mail_failure_issues_no_challenge(): void
    {
        config(['mail.default' => 'log']);
        $this->post(route('profile.password.code'))->assertSessionHasErrorsIn('updatePassword', 'delivery');
        $this->assertNull(session('admin_password'));
        Notification::assertNothingSent();
    }
    public function test_reset_codes_use_the_existing_brevo_transport_with_reset_wording(): void
    {
        config(['services.brevo.admin_mail_key' => 'test-key', 'services.brevo.admin_mail_from' => 'sender@example.test']);
        Http::fake(['https://api.brevo.com/v3/smtp/email' => Http::response(['messageId' => 'test-accepted'], 201)]);
        $this->post(route('profile.password.code'))->assertSessionHas('status', 'password-code-sent');
        Http::assertSent(fn ($request) => $request['to'][0]['email'] === 'admin@example.test'
            && str_contains($request['subject'], 'password reset code')
            && str_contains($request['textContent'], session('admin_password.reference')));
        Notification::assertNothingSent();
    }

    public function test_email_cannot_be_swapped_to_bypass_verification(): void
    {
        $this->patch('/profile', ['name' => 'Profile Admin', 'email' => 'other@example.test'])->assertSessionHasErrors('email');
        $this->assertSame('admin@example.test', $this->admin->refresh()->USR_EMAIL);
    }
    public function test_password_cannot_be_submitted_before_email_verification(): void
    {
        $code = $this->code();
        $this->put('/password', $this->payload($code))->assertSessionHasErrorsIn('updatePassword', 'code');
        $this->assertTrue(Hash::check('old-password', $this->admin->refresh()->USR_PASSWORD));
        $this->get('/profile')->assertDontSee('name="current_password"', false);
    }

    public function test_verified_permission_expires_and_codes_reject_non_numeric_input(): void
    {
        $code = $this->code();
        $this->post(route('profile.password.verify'), ['code' => '12ab34'])->assertSessionHasErrorsIn('updatePassword', 'code');
        $this->verify($code);
        $this->travel(301)->seconds();
        $this->put('/password', $this->payload($code))->assertSessionHasErrorsIn('updatePassword', 'code');
        $this->assertTrue(Hash::check('old-password', $this->admin->refresh()->USR_PASSWORD));
    }

    public function test_profile_name_and_phone_are_editable_with_validation(): void
    {
        $this->patch('/profile', ['name' => 'Updated Admin', 'email' => $this->admin->USR_EMAIL, 'phone' => '09123456789'])
            ->assertRedirect(route('profile.edit'))->assertSessionHasNoErrors();
        $this->assertSame('Updated Admin', $this->admin->refresh()->USR_NAME);
        $this->assertSame('09123456789', $this->admin->USR_MOBILE_NUMBER);
        $this->patch('/profile', ['name' => 'Updated Admin', 'email' => $this->admin->USR_EMAIL])
            ->assertSessionHasNoErrors();
        $this->assertSame('09123456789', $this->admin->refresh()->USR_MOBILE_NUMBER);
        $this->patch('/profile', ['name' => 'Updated Admin', 'email' => $this->admin->USR_EMAIL, 'phone' => '123456789012'])
            ->assertSessionHasErrors('phone');
        User::create(['USR_ID' => 'OTHER1', 'USR_NAME' => 'Other Admin', 'USR_EMAIL' => 'other@example.test',
            'USR_PASSWORD' => Hash::make('another-password'), 'USR_ROLE' => 'ADMIN', 'USR_STATUS' => 'ACTIVE', 'USR_MOBILE_NUMBER' => '09987654321']);
        $this->patch('/profile', ['name' => 'Updated Admin', 'email' => $this->admin->USR_EMAIL, 'phone' => '09987654321'])
            ->assertSessionHasErrors('phone');
        $this->assertSame('09123456789', $this->admin->refresh()->USR_MOBILE_NUMBER);
    }

    public function test_unverified_and_non_admin_sessions_are_blocked(): void
    {
        $this->withSession(['admin_mfa' => []])->post(route('profile.password.code'))->assertRedirect(route('login'));
        $this->admin->update(['USR_ROLE' => 'GENERAL_USER']);
        $this->actingAs($this->admin, 'web')->post(route('profile.password.code'))->assertForbidden();
        Notification::assertNothingSent();
    }
}
