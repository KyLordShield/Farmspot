<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class PremiumPushSender
{
    public function configured(): bool
    {
        return (bool) config('services.onesignal.app_id') && (bool) config('services.onesignal.rest_api_key');
    }

    public function send(object $batch): bool
    {
        if (! $this->configured()) {
            return false;
        }
        $response = Http::withHeaders(['Authorization' => 'Key '.config('services.onesignal.rest_api_key')])->connectTimeout(3)->timeout(5)
            ->post(rtrim(config('services.onesignal.base_url'), '/').'/notifications', [
                'app_id' => config('services.onesignal.app_id'), 'include_aliases' => ['external_id' => [$batch->USR_ID]], 'target_channel' => 'push',
                'headings' => ['en' => $batch->TITLE], 'contents' => ['en' => $batch->BODY], 'idempotency_key' => $batch->ID,
                'small_icon' => config('services.onesignal.small_icon'), 'large_icon' => config('services.onesignal.large_icon'),
                'data' => ['screen' => 'notifications'], 'ttl' => 3600,
            ]);

        if (! $response->successful() || ! $response->json('id') || $response->json('errors')) {
            Log::warning('Premium push was not accepted', ['batch' => $batch->ID, 'status' => $response->status()]);
        }

        return $response->successful() && is_string($response->json('id')) && $response->json('id') !== '' && ! $response->json('errors');
    }
}
