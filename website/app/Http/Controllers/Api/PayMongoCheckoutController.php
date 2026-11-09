<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PremiumCheckout;
use App\Services\PayMongoTestCheckout;
use Illuminate\Http\Request;

class PayMongoCheckoutController extends Controller
{
    public function store(Request $request, PayMongoTestCheckout $service)
    {
        return response()->json(['checkout' => $this->format($service->create($request->user()))]);
    }

    public function show(Request $request, string $id)
    {
        return response()->json(['checkout' => $this->format($this->owned($request, $id))]);
    }

    public function verify(Request $request, string $id, PayMongoTestCheckout $service)
    {
        return response()->json(['checkout' => $this->format($service->refresh($this->owned($request, $id)))]);
    }

    private function owned(Request $request, string $id): PremiumCheckout
    {
        return PremiumCheckout::whereKey($id)->where('USR_ID', $request->user()->USR_ID)->firstOrFail();
    }

    private function format(PremiumCheckout $row): array
    {
        return ['id' => $row->ID, 'status' => $row->STATUS, 'test_mode' => true, 'checkout_url' => $row->CHECKOUT_URL, 'amount' => $row->AMOUNT, 'currency' => $row->CURRENCY, 'payment_reference' => $row->PAYMENT_ID, 'paid_at' => $row->PAID_AT?->toIso8601String(), 'premium_until' => $row->PREMIUM_UNTIL?->toIso8601String()];
    }

    public function returned(Request $request)
    {
        $message = $request->query('result') === 'complete' ? 'Return to FarmSpot and tap Check payment. Premium activates only after server verification.' : 'Checkout was closed. Return to FarmSpot to resume or check your test payment.';

        return response('<!doctype html><html lang="en"><meta name="viewport" content="width=device-width, initial-scale=1"><title>FarmSpot test checkout</title><body style="font-family:system-ui;padding:32px;max-width:480px;margin:auto"><h1>FarmSpot test checkout</h1><p>TEST MODE — NO REAL CHARGE</p><p>'.$message.'</p></body></html>')->header('Content-Type', 'text/html; charset=UTF-8');
    }

    public function webhook(Request $request, PayMongoTestCheckout $service)
    {
        $secret = (string) config('paymongo.webhook_secret');
        abort_if($secret === '', 503, 'Test webhook is not configured.');
        $parts = [];
        foreach (explode(',', (string) $request->header('Paymongo-Signature')) as $part) {
            $pair = explode('=', trim($part), 2);
            if (count($pair) === 2) {
                $parts[$pair[0]] = $pair[1];
            }
        }
        $timestamp = $parts['t'] ?? '';
        $signature = $parts['te'] ?? '';
        abort_unless(ctype_digit($timestamp) && abs(now()->timestamp - (int) $timestamp) <= 300 && preg_match('/^[a-f0-9]{64}$/i', $signature) && hash_equals(hash_hmac('sha256', $timestamp.'.'.$request->getContent(), $secret), $signature), 401, 'Invalid webhook signature.');
        $payload = $request->json()->all();
        $type = data_get($payload, 'data.attributes.type') ?? data_get($payload, 'data.type');
        if ($type !== 'checkout_session.payment.paid') {
            return response()->json(['received' => true]);
        }
        $session = data_get($payload, 'data.attributes.data') ?? data_get($payload, 'data.data');
        abort_unless(is_array($session) && data_get($session, 'attributes.livemode') === false, 422, 'Only test checkout events are supported.');
        $row = PremiumCheckout::where('SESSION_ID', $session['id'] ?? '')->first();
        if ($row) {
            $service->refresh($row);
        }

        return response()->json(['received' => true]);
    }
}
