<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class RateLimitingTest extends TestCase
{
    public function test_malformed_login_email_reaches_validation(): void
    {
        $this->postJson('/api/login', ['email' => ['test@example.com']])->assertUnprocessable();
    }

    public function test_app_login_is_limited_and_recovers_after_a_minute(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/login', ['email' => 'test@example.com'])->assertUnprocessable();
        }

        $this->postJson('/api/login', ['email' => ' TEST@example.com '])
            ->assertStatus(429)->assertHeader('Retry-After');

        $this->travel(61)->seconds();
        $this->postJson('/api/login', ['email' => 'test@example.com'])->assertUnprocessable();
    }

    public function test_rotating_login_emails_does_not_bypass_ip_limit(): void
    {
        for ($i = 0; $i < 20; $i++) {
            $this->postJson('/api/login', ['email' => "test{$i}@example.com"])->assertUnprocessable();
        }

        $this->postJson('/api/login', ['email' => 'another@example.com'])->assertStatus(429);
        $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.2'])
            ->postJson('/api/login', ['email' => 'another@example.com'])->assertUnprocessable();
    }

    public function test_registration_is_limited_before_validation(): void
    {
        for ($i = 0; $i < 3; $i++) {
            $this->postJson('/api/register')->assertUnprocessable();
        }

        $this->postJson('/api/register')->assertStatus(429)->assertHeader('Retry-After');
    }

    public function test_website_login_is_limited(): void
    {
        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/login', ['email' => 'admin@example.com'])->assertUnprocessable();
        }

        $this->postJson('/login', ['email' => 'admin@example.com'])->assertStatus(429);
    }

    public function test_general_api_and_website_limits_apply(): void
    {
        Route::middleware('api')->get('/api/rate-test', fn () => response()->noContent());
        Route::middleware('web')->get('/rate-test', fn () => response()->noContent());

        for ($i = 0; $i < 180; $i++) {
            $this->getJson('/api/rate-test')->assertNoContent();
        }
        $this->getJson('/api/rate-test')->assertStatus(429);

        for ($i = 0; $i < 120; $i++) {
            $this->get('/rate-test')->assertNoContent();
        }
        $this->get('/rate-test')->assertStatus(429)->assertHeader('Retry-After');
    }

    public function test_writes_share_account_budget_but_other_users_and_reads_are_independent(): void
    {
        Route::middleware(['api', 'auth:sanctum'])->post('/api/rate-write', fn () => response()->noContent());
        Route::middleware(['api', 'auth:sanctum'])->get('/api/rate-read', fn () => response()->noContent());

        $first = new User(['USR_ID' => 'FIRST1']);
        $second = new User(['USR_ID' => 'SECOND']);
        $this->actingAs($first, 'sanctum');
        for ($i = 0; $i < 60; $i++) {
            $this->postJson('/api/rate-write')->assertNoContent();
        }

        $this->withServerVariables(['REMOTE_ADDR' => '192.0.2.3'])
            ->postJson('/api/rate-write')->assertStatus(429);
        $this->getJson('/api/rate-read')->assertNoContent();
        $this->actingAs($second, 'sanctum')->postJson('/api/rate-write')->assertNoContent();
    }
}
