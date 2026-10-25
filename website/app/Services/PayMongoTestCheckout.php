<?php

namespace App\Services;

use App\Models\PremiumCheckout;
use App\Models\User;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

class PayMongoTestCheckout
{
    public function ready(): bool
    {
        return (bool) config('paymongo.enabled') && str_starts_with((string) config('paymongo.secret_key'), 'sk_test_');
    }

    private function client()
    {
        abort_unless($this->ready(), 503, 'PayMongo test checkout is not configured. A secret test key is required.');

        return Http::withBasicAuth(config('paymongo.secret_key'), '')->acceptJson()->asJson()->connectTimeout(5)->timeout(15);
    }

    private function request(string $method, string $path, ?array $payload = null, ?string $key = null): array
    {
        try {
            $client = $this->client();
            if ($key) {
                $client = $client->withHeaders(['Idempotency-Key' => $key]);
            }
            $response = $method === 'GET' ? $client->get('https://api.paymongo.com'.$path) : $client->post('https://api.paymongo.com'.$path, $payload);
        } catch (ConnectionException $e) {
            abort(503, 'PayMongo could not be reached. Your checkout is saved; please retry.');
        }
        if (! $response->successful()) {
            abort(502, $response->status() === 401 ? 'PayMongo did not accept the test key. Check the backend configuration.' : 'PayMongo could not complete the test checkout request. Check your test payment methods or try again.');
        }
        $data = $response->json('data');
        abort_unless(is_array($data), 502, 'PayMongo returned an unexpected response.');

        return $data;
    }

    public function create(User $actor): PremiumCheckout
    {
        abort_unless($this->ready(), 503, 'PayMongo test checkout is not configured.');
        abort_unless($actor->USR_ROLE === 'GENERAL_USER', 403);
        $order = DB::transaction(function () use ($actor) {
            $user = User::whereKey($actor->USR_ID)->lockForUpdate()->firstOrFail();
            abort_if($user->USR_IS_PREMIUM, 409, 'Premium is already active on this account.');
            $previous = PremiumCheckout::where('USR_ID', $user->USR_ID)->whereIn('STATUS', ['CREATING', 'PENDING'])->orderByDesc('CREATED_AT')->first();
            if ($previous) {
                // Do not silently create another payable checkout after an uncertain timeout.
                abort_if($previous->CREATED_AT->lt(now()->subHours(23)), 409, 'This older checkout needs to be checked before a replacement is created.');

                return $previous;
            }
            $id = (string) Str::uuid();
            $return = rtrim(config('paymongo.return_base_url'), '/').'/api/paymongo/return';

            return PremiumCheckout::create(['ID' => $id, 'USR_ID' => $user->USR_ID, 'AMOUNT' => config('paymongo.amount'), 'CURRENCY' => 'PHP', 'CREATED_AT' => now(), 'UPDATED_AT' => now(),
                'CREATE_PAYLOAD' => ['data' => ['attributes' => [
                    'line_items' => [['name' => 'FarmSpot Business Premium - Monthly Plan', 'amount' => config('paymongo.amount'), 'currency' => 'PHP', 'quantity' => 1]],
                    'payment_method_types' => config('paymongo.methods'), 'description' => 'One month of FarmSpot Business Premium, including buy requests, weekly sourcing, saved farms and crop alerts. No automatic renewal.',
                    'reference_number' => $id, 'metadata' => ['farmspot_checkout_id' => $id],
                    'success_url' => $return.'?result=complete', 'cancel_url' => $return.'?result=cancelled',
                    'send_email_receipt' => false,
                ]]]]);
        });
        if ($order->SESSION_ID) {
            return $order;
        }
        $session = $this->request('POST', '/v2/checkout_sessions', $order->CREATE_PAYLOAD, $order->ID);
        // v2 creation omits reference_number; retrieve the canonical session before accepting it.
        abort_unless(($session['type'] ?? null) === 'checkout_session' && is_string($session['id'] ?? null) && str_starts_with($session['id'], 'cs_'), 502, 'Invalid checkout session.');
        $session = $this->request('GET', '/v1/checkout_sessions/'.rawurlencode($session['id']));
        $this->validateSession($order, $session, false);
        $url = data_get($session, 'attributes.checkout_url');
        abort_unless($this->validUrl($url), 502, 'PayMongo returned an invalid checkout URL.');
        DB::transaction(function () use ($order, $session, $url) {
            $row = PremiumCheckout::whereKey($order->ID)->lockForUpdate()->firstOrFail();
            if ($row->SESSION_ID) {
                return;
            }
            $row->SESSION_ID = $session['id'];
            $row->CHECKOUT_URL = $url;
            $row->STATUS = 'PENDING';
            $row->UPDATED_AT = now();
            $row->save();
        });

        return $order->fresh();
    }

    public function validUrl(?string $url): bool
    {
        $host = parse_url($url ?? '', PHP_URL_HOST);

        return parse_url($url ?? '', PHP_URL_SCHEME) === 'https' && is_string($host) && ($host === 'paymongo.com' || str_ends_with($host, '.paymongo.com'));
    }

    private function validateSession(PremiumCheckout $order, array $session, bool $retrieved = true): void
    {
        abort_unless(($session['type'] ?? null) === 'checkout_session' && is_string($session['id'] ?? null) && str_starts_with($session['id'], 'cs_'), 502, 'Invalid checkout session.');
        abort_unless(data_get($session, 'attributes.livemode') === false, 422, 'Live-mode payments are not supported.');
        if ($retrieved) {
            abort_unless($session['id'] === $order->SESSION_ID, 422, 'Checkout session mismatch.');
        }
        $ref = data_get($session, 'attributes.reference_number') ?? data_get($session, 'attributes.metadata.farmspot_checkout_id');
        abort_unless($ref === $order->ID, 422, 'Checkout reference mismatch.');
    }

    public function refresh(PremiumCheckout $order): PremiumCheckout
    {
        if ($order->STATUS === 'PAID' || ! $order->SESSION_ID) {
            return $order;
        }
        $session = $this->request('GET', '/v1/checkout_sessions/'.rawurlencode($order->SESSION_ID));
        $this->validateSession($order, $session);
        $payments = data_get($session, 'attributes.payments', []);
        $paid = collect(is_array($payments) ? $payments : [])->first(fn ($p) => data_get($p, 'attributes.status') === 'paid');
        if ($paid) {
            $attributes = $paid['attributes'];
            abort_unless(($attributes['livemode'] ?? false) === false && ($attributes['amount'] ?? null) === $order->AMOUNT && ($attributes['currency'] ?? null) === 'PHP' && is_string($paid['id'] ?? null), 422, 'Payment amount, currency or environment does not match this test order.');

            return $this->activate($order, $paid['id']);
        }
        if (in_array(data_get($session, 'attributes.status'), ['expired', 'cancelled'], true)) {
            PremiumCheckout::whereKey($order->ID)->where('STATUS', '!=', 'PAID')->update(['STATUS' => 'EXPIRED', 'UPDATED_AT' => now()]);
        }

        return $order->fresh();
    }

    private function activate(PremiumCheckout $order, string $payment): PremiumCheckout
    {
        return DB::transaction(function () use ($order, $payment) {
            $user = User::whereKey($order->USR_ID)->lockForUpdate()->firstOrFail();
            $row = PremiumCheckout::whereKey($order->ID)->lockForUpdate()->firstOrFail();
            if ($row->STATUS === 'PAID') {
                return $row;
            }
            abort_unless($user->USR_STATUS === 'ACTIVE', 409, 'This account is not active.');
            // Credit this payment once, extending an existing period only for a distinct paid order.
            $base = $user->USR_IS_PREMIUM ? $user->USR_PREMIUM_EXPIRES_AT->copy() : now();
            if (! $user->USR_IS_PREMIUM) {
                $user->USR_PREMIUM_STARTED_AT = now();
            }
            $user->USR_PREMIUM_EXPIRES_AT = $base->addMonthNoOverflow();
            $user->save();
            $row->PAYMENT_ID = $payment;
            $row->STATUS = 'PAID';
            $row->PAID_AT = now();
            $row->PREMIUM_UNTIL = $user->USR_PREMIUM_EXPIRES_AT;
            $row->UPDATED_AT = now();
            $row->save();

            return $row;
        });
    }
}
