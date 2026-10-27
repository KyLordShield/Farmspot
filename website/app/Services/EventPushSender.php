<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;

class EventPushSender
{
    public function configured(): bool
    {
        return (bool) config('services.onesignal.app_id') && (bool) config('services.onesignal.rest_api_key');
    }

    public function send(object $batch, object $notice): bool
    {
        $response = Http::withHeaders(['Authorization' => 'Key '.config('services.onesignal.rest_api_key')])
            ->connectTimeout(3)->timeout(5)
            ->post(rtrim(config('services.onesignal.base_url'), '/').'/notifications', [
                'app_id' => config('services.onesignal.app_id'),
                'include_aliases' => ['external_id' => json_decode($batch->USERS, true)],
                'target_channel' => 'push',
                'headings' => ['en' => $notice->TITLE],
                'contents' => ['en' => $notice->BODY],
                'idempotency_key' => $batch->ID,
                'data' => ['screen' => 'notifications'],
                'small_icon' => config('services.onesignal.small_icon'),
                'large_icon' => config('services.onesignal.large_icon'),
                'ttl' => 86400,
            ]);

        // A nonempty ID means accepted, including partial subscription matches.
        // Keep retrying unaccepted requests with the SAME payload and UUID.
        return $response->successful() && is_string($response->json('id')) && $response->json('id') !== '';
    }
}
