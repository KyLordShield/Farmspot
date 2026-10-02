<?php

namespace App\Services;

use App\Models\UserNotification;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * The one place a notification is ever created.
 *
 * Every caller — an admin taking a listing down, the hourly expiry commands, a
 * moderator answering a report — goes through notify(), so the inbox row and the
 * push can never disagree about whether the user was told.
 *
 * The ordering is deliberate and is the whole design: the database row is
 * written FIRST and the push is attempted SECOND, inside a try/catch. The inbox
 * row is the source of truth; the push is only a nudge to open the app. A
 * farmer on a weak connection, or a OneSignal outage, or a missing API key must
 * never roll back an admin action that already succeeded — the alternative
 * would be a listing that is genuinely off sale but whose seller was never
 * informed, which is worse than a late notification.
 */
class NotificationService
{
    /**
     * Record a notification for one user, then try to push it to their phone.
     *
     * $refId is the record the notification is about, normally an LST_ID. It is
     * what the app deep-links to, and it is also the de-duplication key: the
     * hourly commands check NOTIF_TYPE + NOTIF_REF_ID before calling this, so a
     * listing that stays unexpired is never warned about twice.
     */
    public function notify(
        string $usrId,
        string $type,
        string $title,
        string $body,
        ?string $refId = null
    ): void {
        $notification = UserNotification::create([
            'NOTIF_ID' => UserNotification::newId(),
            'USR_ID' => $usrId,
            'NOTIF_TYPE' => $type,
            'NOTIF_TITLE' => $title,
            'NOTIF_BODY' => $body,
            'NOTIF_REF_ID' => $refId,
            'NOTIF_IS_READ' => 0,
            'NOTIF_CREATED_AT' => now(),
        ]);

        // Everything below is best-effort. The row above is already committed.
        $this->push($usrId, $notification->NOTIF_TITLE, $notification->NOTIF_BODY);
    }

    /**
     * Push-only. No inbox row is written.
     *
     * For the one case where a push summarises something rather than
     * announcing it: a farmer with several listings about to expire gets one
     * combined alert rather than a burst, but the inbox still lists each
     * listing separately so they can tell which crop to update. Writing a
     * summary row as well would put a notification in the list that points at
     * no particular listing.
     *
     * Same swallow-everything rule as notify(): a push is never load-bearing.
     */
    public function pushOnly(string $usrId, string $title, string $body): void
    {
        $this->push($usrId, $title, $body);
    }

    /**
     * Send the OneSignal push, swallowing any failure.
     *
     * Returns void on purpose: there is no caller that can do anything useful
     * with a push error, and letting one bubble up would mean a network blip
     * could abort a moderator's takedown halfway through.
     */
    private function push(string $usrId, string $title, string $body): void
    {
        $appId = config('services.onesignal.app_id');
        $restKey = config('services.onesignal.rest_api_key');

        // Not configured yet. Skipping silently is intentional — the inbox row is
        // already written and the app reads it on next open, so nothing is lost
        // by not having push.
        if (empty($appId) || empty($restKey)) {
            return;
        }

        try {
            $response = Http::withHeaders([
                'Authorization' => 'Basic '.$restKey,
                'Content-Type' => 'application/json',
            ])
                ->timeout(5)
                ->post(rtrim(config('services.onesignal.base_url'), '/').'/notifications', [
                    'app_id' => $appId,
                    // include_aliases targets the exact devices registered under
                    // this user's external_id. Going through the alias rather
                    // than a subscription id is what lets a notification reach
                    // every device that person has signed in on, including a new
                    // phone they have not pushed from yet.
                    'include_aliases' => [
                        'external_id' => [$usrId],
                    ],
                    'target_channel' => 'push',
                    'headings' => [
                        'en' => $title,
                    ],
                    'contents' => [
                        'en' => $body,
                    ],
                ]);

            if (! $response->successful()) {
                // OneSignal answers 200 with a per-recipient "errors" array when
                // it accepts the request but could not deliver it, so a plain
                // status check is not enough to notice a dead push.
                Log::warning('[notifications] OneSignal rejected the push', [
                    'usr_id' => $usrId,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }
        } catch (\Throwable $e) {
            Log::warning('[notifications] OneSignal push failed', [
                'usr_id' => $usrId,
                'message' => $e->getMessage(),
            ]);
        }
    }
}