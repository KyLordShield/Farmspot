<?php

namespace Tests\Feature;

use App\Models\PremiumCheckout;
use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\Client\Factory;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PayMongoCheckoutTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.default' => 'sqlite', 'database.connections.sqlite.database' => ':memory:',
            'paymongo.enabled' => true, 'paymongo.secret_key' => 'sk_test_fake', 'paymongo.webhook_secret' => 'test_webhook']);
        DB::purge('sqlite');
        Schema::create('user', function (Blueprint $t) {
            $t->string('USR_ID')->primary();
            $t->string('USR_NAME');
            $t->string('USR_EMAIL')->unique();
            $t->string('USR_PASSWORD');
            $t->string('USR_STATUS');
            $t->string('USR_ROLE');
            $t->boolean('USR_IS_SELLER')->default(false);
        });
        (require database_path('migrations/2026_10_24_000001_add_premium_access_to_user_table.php'))->up();
        (require database_path('migrations/2026_10_25_000003_create_premium_checkout.php'))->up();
        Http::preventStrayRequests();
    }

    private function fake(array $responses): void
    {
        Http::swap(new Factory);
        Http::preventStrayRequests();
        Http::fake($responses);
    }

    private function login(string $id = 'BUY001'): User
    {
        $user = User::create(['USR_ID' => $id, 'USR_NAME' => 'Checkout test', 'USR_EMAIL' => $id.'@example.test',
            'USR_PASSWORD' => bcrypt('password'), 'USR_STATUS' => 'ACTIVE', 'USR_ROLE' => 'GENERAL_USER']);
        Sanctum::actingAs($user);

        return $user;
    }

    private function sessionFixture(PremiumCheckout $row, bool $paid = false): array
    {
        return ['id' => $row->SESSION_ID ?? 'cs_test_'.$row->ID, 'type' => 'checkout_session', 'attributes' => [
            'livemode' => false, 'reference_number' => $row->ID, 'checkout_url' => 'https://checkout.paymongo.com/test',
            'status' => 'active', 'payments' => $paid ? [['id' => 'pay_test_001', 'type' => 'payment', 'attributes' => [
                'livemode' => false, 'status' => 'paid', 'amount' => 9900, 'currency' => 'PHP']]] : []]];
    }

    private function fakeCreate(): void
    {
        $this->fake(['https://api.paymongo.com/v1/checkout_sessions/*' => function ($request) {
            $id = basename($request->url());
            $row = PremiumCheckout::where('ID', substr($id, strlen('cs_test_')))->firstOrFail();

            return Http::response(['data' => $this->sessionFixture($row)]);
        }, 'https://api.paymongo.com/v2/checkout_sessions' => function ($request) {
            $row = PremiumCheckout::findOrFail($request['data']['attributes']['reference_number']);
            $this->assertSame(9900, $request['data']['attributes']['line_items'][0]['amount']);
            $this->assertTrue($request->hasHeader('Idempotency-Key', $row->ID));

            return Http::response(['data' => $this->sessionFixture($row)]);
        }]);
    }

    private function createOrder(): PremiumCheckout
    {
        $this->fakeCreate();
        $this->postJson('/api/premium/checkouts', ['amount' => 1, 'USR_ID' => 'OTHER'])->assertOk()->assertJsonPath('checkout.amount', 9900);

        return PremiumCheckout::firstOrFail();
    }

    public function test_pending_checkout_reuses_session_and_cannot_activate_via_return_or_simulation(): void
    {
        $user = $this->login();
        $row = $this->createOrder();
        $this->postJson('/api/premium/checkouts')->assertOk()->assertJsonPath('checkout.id', $row->ID);
        Http::assertSentCount(2);
        $this->get('/api/paymongo/return?result=complete')->assertOk();
        $this->postJson('/api/premium/simulate-purchase')->assertForbidden();
        $this->fake(['https://api.paymongo.com/v1/*' => Http::response(['data' => $this->sessionFixture($row)])]);
        $this->postJson('/api/premium/checkouts/'.$row->ID.'/verify')->assertOk()->assertJsonPath('checkout.status', 'PENDING');
        $this->assertFalse($user->fresh()->USR_IS_PREMIUM);
    }

    public function test_verified_payment_credits_exactly_one_month_once(): void
    {
        $this->travelTo(now()->setDate(2026, 1, 31)->startOfDay());
        $user = $this->login();
        $row = $this->createOrder();
        $this->fake(['https://api.paymongo.com/v1/*' => Http::response(['data' => $this->sessionFixture($row, true)])]);
        $url = '/api/premium/checkouts/'.$row->ID.'/verify';
        $this->postJson($url)->assertOk()->assertJsonPath('checkout.status', 'PAID');
        $this->assertSame('2026-02-28', $user->fresh()->USR_PREMIUM_EXPIRES_AT->toDateString());
        $this->travel(1)->days();
        $this->postJson($url)->assertOk();
        $this->assertSame('2026-02-28', $user->fresh()->USR_PREMIUM_EXPIRES_AT->toDateString());
        $this->postJson('/api/premium/checkouts')->assertStatus(409);
        $this->travelBack();
    }

    public function test_ownership_and_authentication(): void
    {
        $this->postJson('/api/premium/checkouts')->assertUnauthorized();
        $this->login();
        $row = $this->createOrder();
        $this->login('BUY002');
        $this->getJson('/api/premium/checkouts/'.$row->ID)->assertNotFound();
        $this->postJson('/api/premium/checkouts/'.$row->ID.'/verify')->assertNotFound();
    }

    public function test_live_key_is_never_sent(): void
    {
        $user = $this->login();
        config(['paymongo.secret_key' => 'sk_live_not_allowed']);
        $this->postJson('/api/premium/checkouts')->assertStatus(503);
        Http::assertNothingSent();
        $this->assertFalse($user->fresh()->USR_IS_PREMIUM);
    }

    public function test_mismatched_paid_responses_never_grant_access(): void
    {
        $user = $this->login();
        $row = $this->createOrder();
        foreach (['amount', 'currency', 'livemode', 'reference'] as $invalid) {
            $session = $this->sessionFixture($row, true);
            if ($invalid === 'reference') {
                $session['attributes']['reference_number'] = 'another_order';
            } elseif ($invalid === 'livemode') {
                $session['attributes']['livemode'] = true;
            } else {
                $session['attributes']['payments'][0]['attributes'][$invalid] = $invalid === 'amount' ? 1 : 'USD';
            }
            $this->fake(['https://api.paymongo.com/v1/*' => Http::response(['data' => $session])]);
            $this->postJson('/api/premium/checkouts/'.$row->ID.'/verify')->assertStatus(422);
            $this->assertFalse($user->fresh()->USR_IS_PREMIUM);
        }
    }

    public function test_timeout_retry_uses_same_order_payload_and_idempotency_key(): void
    {
        $this->login();
        $this->fake(['https://api.paymongo.com/*' => Http::failedConnection()]);
        $this->postJson('/api/premium/checkouts')->assertStatus(503);
        $row = PremiumCheckout::firstOrFail();
        $payload = $row->CREATE_PAYLOAD;
        $this->fakeCreate();
        $this->postJson('/api/premium/checkouts')->assertOk()->assertJsonPath('checkout.id', $row->ID);
        $this->assertSame(1, PremiumCheckout::count());
        $this->assertSame($payload, $row->fresh()->CREATE_PAYLOAD);
    }

    public function test_webhook_requires_fresh_signature_and_verifies_with_provider(): void
    {
        $user = $this->login();
        $row = $this->createOrder();
        $payload = json_encode(['data' => ['attributes' => ['type' => 'checkout_session.payment.paid', 'data' => $this->sessionFixture($row, true)]]]);
        $this->call('POST', '/api/paymongo/webhook', [], [], [], ['CONTENT_TYPE' => 'application/json'], $payload)->assertUnauthorized();
        $this->fake(['https://api.paymongo.com/v1/*' => Http::response(['data' => $this->sessionFixture($row, true)])]);
        foreach ([now()->timestamp - 600, now()->timestamp] as $timestamp) {
            $sig = 't='.$timestamp.',te='.hash_hmac('sha256', $timestamp.'.'.$payload, 'test_webhook');
            $response = $this->call('POST', '/api/paymongo/webhook', [], [], [], ['CONTENT_TYPE' => 'application/json', 'HTTP_PAYMONGO_SIGNATURE' => $sig], $payload);
            if ($timestamp < now()->timestamp - 300) {
                $response->assertUnauthorized();
                $this->assertFalse($user->fresh()->USR_IS_PREMIUM);
            } else {
                $response->assertOk();
            }
        }
        $this->assertTrue($user->fresh()->USR_IS_PREMIUM);
    }
}
