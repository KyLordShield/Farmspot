<?php

namespace Tests\Feature\Auth;

use App\Models\User;
use App\Notifications\AdminSignInCode;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class AdminMfaTest extends TestCase
{
    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        config([
            'app.key' => 'base64:'.base64_encode(random_bytes(32)),
            'mail.default' => 'smtp',
        ]);
        Notification::fake();

        Schema::create('user', function (Blueprint $table) {
            $table->string('USR_ID')->primary();
            $table->string('USR_EMAIL')->unique();
            $table->string('USR_PASSWORD');
            $table->string('USR_ROLE');
            $table->string('USR_STATUS');
        });

        $this->admin = User::create([
            'USR_ID' => 'ADMIN1',
            'USR_EMAIL' => 'admin@example.test',
            'USR_PASSWORD' => Hash::make('test-password'),
            'USR_ROLE' => 'ADMIN',
            'USR_STATUS' => 'ACTIVE',
        ]);
    }

    public function test_password_alone_cannot_open_admin_pages_or_api(): void
    {
        $this->login()->assertRedirect(route('admin.mfa'));
        $this->get('/users')->assertRedirect(route('admin.mfa'));
        $this->getJson('/api/admin/seller-requests')->assertForbidden();
        $this->get('/admin/verify')->assertOk()->assertSee('Check your email');
    }

    public function test_emailed_code_opens_admin_pages_and_is_single_use(): void
    {
        $this->login()->assertRedirect(route('admin.mfa'));

        $code = $this->sentCode();
        $pending = session('admin_mfa');
        $this->assertNotSame($code, $pending['code_hash']);
        $notification = Notification::sent($this->admin, AdminSignInCode::class)->last();
        $this->get('/admin/verify')->assertSee($notification->reference)->assertDontSee($code);

        $this->post('/admin/verify', ['code' => chunk_split($code, 3, "\u{202F}")])->assertRedirect('/dashboard');
        $this->get('/confirm-password')->assertOk()->assertHeader('Cache-Control', 'no-store, private');
        $this->withSession(['admin_mfa' => $pending])->postJson('/admin/verify', ['code' => $code])
            ->assertUnprocessable();
    }

    public function test_resend_has_a_cooldown_and_replaces_the_challenge(): void
    {
        $this->login()->assertRedirect(route('admin.mfa'));
        $oldNonce = session('admin_mfa.nonce');
        $oldReference = session('admin_mfa.reference');
        $this->post('/admin/verify/resend')->assertSessionHasErrors('delivery');
        Notification::assertCount(1);

        $this->travel(61)->seconds();
        $this->post('/admin/verify/resend')->assertSessionDoesntHaveErrors();
        Notification::assertCount(2);
        $this->assertNotSame($oldNonce, session('admin_mfa.nonce'));
        $this->assertNotSame($oldReference, session('admin_mfa.reference'));
        $this->travel(4)->minutes();
        $this->post('/admin/verify', ['code' => $this->sentCode()])->assertRedirect('/dashboard');
    }

    public function test_mfa_attempts_are_limited_across_ip_addresses(): void
    {
        $this->login()->assertRedirect(route('admin.mfa'));
        $wrongCode = $this->sentCode() === '000000' ? '000001' : '000000';
        for ($i = 0; $i < 5; $i++) {
            $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.'.($i + 1)])
                ->postJson('/admin/verify', ['code' => $wrongCode])->assertUnprocessable();
        }
        $this->postJson('/admin/verify', ['code' => $this->sentCode()])->assertStatus(429)->assertHeader('Retry-After');
    }

    public function test_challenge_expires_after_five_minutes(): void
    {
        $this->login()->assertRedirect(route('admin.mfa'));
        $this->travel(5)->minutes();

        $this->post('/admin/verify', ['code' => $this->sentCode()])
            ->assertRedirect(route('login'))->assertSessionHasErrors('email');
        $this->get('/users')->assertRedirect('/login');
        $this->assertGuest('web');
    }

    public function test_idle_admin_session_expires(): void
    {
        $this->login()->assertRedirect(route('admin.mfa'));
        $this->post('/admin/verify', ['code' => $this->sentCode()])->assertRedirect('/dashboard');

        $this->travel(30)->minutes();
        $this->get('/users')->assertRedirect('/login');
        $this->assertGuest('web');
    }

    public function test_log_mailer_cannot_issue_admin_codes(): void
    {
        config(['mail.default' => 'log']);
        $this->login()->assertSessionHasErrors('delivery');
        Notification::assertNothingSent();
        $this->assertNull(session('admin_mfa.nonce'));
        $this->get('/users')->assertRedirect(route('admin.mfa'));
    }

    private function sentCode(): string
    {
        return Notification::sent($this->admin, AdminSignInCode::class)->last()->code;
    }

    private function login()
    {
        return $this->post('/login', ['email' => 'admin@example.test', 'password' => 'test-password']);
    }
}
