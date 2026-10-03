<?php

namespace App\Services;

use App\Models\UserNotification;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Symfony\Component\Process\PhpExecutableFinder;

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
     *
     * $sendPush is false for the harvest reminder, which is the one case where
     * several rows are written for one farmer at once and a single combined
     * alert is sent afterwards with pushOnly(). Writing those rows with the
     * default would push once per listing, which is the burst of alerts
     * pushOnly() exists to avoid. The row is still written here, so there is
     * still exactly one code path that creates notifications.
     */
    public function notify(
        string $usrId,
        string $type,
        string $title,
        string $body,
        ?string $refId = null,
        bool $sendPush = true
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

        if (! $sendPush) {
            return;
        }

        // Everything below is best-effort. The row above is already committed.
        $this->push($usrId, $notification->NOTIF_TITLE, $notification->NOTIF_BODY);
    }

    /**
     * Tell a farmer their farm just went live.
     *
     * Two things live here rather than in the controllers, because both call
     * sites have to agree on them: the wording, and the de-duplication. Farm
     * creation can reach the "live" state two ways — instant approval on
     * submit, or a later admin approval — and a farm must only ever be
     * announced once even if both fire.
     *
     * De-duplication is on NOTIF_REF_ID = FRM_ID, so it is per farm and not per
     * farmer: a farmer's second farm is a genuinely separate thing to announce.
     */
    public function notifyFarmLive(
        string $usrId,
        string $farmId,
        string $farmName,
        bool $isFirstFarm
    ): void {
        $alreadySent = UserNotification::where('USR_ID', $usrId)
            ->where('NOTIF_TYPE', 'SETUP_COMPLETE')
            ->where('NOTIF_REF_ID', $farmId)
            ->exists();

        if ($alreadySent) {
            return;
        }

        // The first farm gets the "add your first crop" nudge because the
        // screen they land on is genuinely empty. A later farm already has crops
        // somewhere, so telling them to add their first one would be nonsense.
        $title = $isFirstFarm ? 'Your farm is live' : 'Your new farm is live';

        $body = $isFirstFarm
            ? "Your farm {$farmName} is now on the map. Add your first crop so buyers can find you."
            : "{$farmName} is now on the map. Add a crop so buyers can find it.";

        $this->notify($usrId, 'SETUP_COMPLETE', $title, $body, $farmId);
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

        // A push is a courtesy layer on top of the inbox row, so it must never
        // be the reason a farmer waits. Sending it inline made every action that
        // notifies — creating a farm, approving a seller — block on OneSignal
        // first. On a weak connection that added seconds to an otherwise instant
        // tap, and when DNS stalled it dragged the request into PHP's 60 second
        // execution limit.
        //
        // For HTTP requests the send is handed to a detached background process,
        // so the response goes out as soon as the work is safely committed and
        // the push follows on its own. A detached process is used rather than
        // app()->terminating() because PHP flushes the response body at script
        // end: under mod_php (XAMPP/Apache) a terminating callback still runs
        // before the farmer's phone sees the reply, so the wait would remain.
        //
        // Console commands send inline: there is no response to get out of the
        // way of, and the harvest reminder runs hourly and must not depend on a
        // background process being able to spawn.
        if (! app()->runningInConsole() && $this->sendInBackground($usrId, $title, $body)) {
            return;
        }

        $this->sendPush($appId, $restKey, $usrId, $title, $body);
    }

    /**
     * Hands the push to a detached `notifications:send-push` process.
     *
     * Returns false when the process could not be started, so the caller can
     * fall back to sending inline rather than dropping the push. Any failure
     * here is deliberately swallowed: the inbox row is already written and is
     * what the app actually reads.
     */
    private function sendInBackground(string $usrId, string $title, string $body): bool
    {
        $payload = base64_encode((string) json_encode([
            'usr_id' => $usrId,
            'title' => $title,
            'body' => $body,
        ], JSON_UNESCAPED_UNICODE));

        try {
            // PHP_BINARY cannot be trusted here. Under mod_php it resolves to
            // httpd.exe, so the "background process" would have been a second
            // web server complaining it could not retrieve its generation from
            // the parent. PhpExecutableFinder deliberately ignores PHP_BINARY
            // outside the cli SAPIs and locates the real php binary instead.
            $php = (new PhpExecutableFinder())->find(false);

            if ($php === false) {
                return false;
            }

            $nullDevice = DIRECTORY_SEPARATOR === '\\' ? 'NUL' : '/dev/null';

            // All three standard streams are pointed at the null device. If the
            // child inherited this request's stdout it would hold the connection
            // open, and the farmer would sit waiting out the push instead of
            // getting their reply.
            $descriptors = [
                0 => ['file', $nullDevice, 'r'],
                1 => ['file', $nullDevice, 'a'],
                2 => ['file', $nullDevice, 'a'],
            ];

            $pipes = [];

            // bypass_shell with an array command means no shell sits in between,
            // and the arguments need no manual quoting.
            $process = proc_open(
                [$php, base_path('artisan'), 'notifications:send-push', $payload],
                $descriptors,
                $pipes,
                base_path(),
                null,
                ['bypass_shell' => true]
            );

            if (! is_resource($process)) {
                return false;
            }

            // Deliberately not proc_close(): that waits for the child, which is
            // the very thing being avoided. Letting the handle go at the end of
            // the request leaves the child running to finish its job - unlike a
            // Symfony Process object, a proc_open handle is released without
            // terminating the child.
            return true;
        } catch (\Throwable $e) {
            Log::warning('[notifications] could not background the push, sending inline', [
                'usr_id' => $usrId,
                'message' => $e->getMessage(),
            ]);

            return false;
        }
    }

    /**
     * Sends a push straight away, in this process. Used by console commands and
     * as the fallback whenever backgrounding is unavailable.
     */
    public function sendPushNow(string $usrId, string $title, string $body): void
    {
        $appId = config('services.onesignal.app_id');
        $restKey = config('services.onesignal.rest_api_key');

        if (empty($appId) || empty($restKey)) {
            return;
        }

        $this->sendPush($appId, $restKey, $usrId, $title, $body);
    }

    /**
     * The actual OneSignal call. Always wrapped so that neither a network
     * failure nor an unreachable host can escape and disturb whatever action
     * triggered the notification.
     */
    private function sendPush(string $appId, string $restKey, string $usrId, string $title, string $body): void
    {
        try {
            $response = Http::withHeaders([
                // "Key", not the old v1 "Basic". Every key the dashboard issues
                // today starts with os_v2_app_ and the v2 endpoint answers 401
                // to a Basic header, which used to mean every push was
                // swallowed with nothing but a log line to show for it.
                'Authorization' => 'Key '.$restKey,
                'Content-Type' => 'application/json',
            ])
                // connectTimeout is the one that matters on a bad connection.
                // timeout(5) bounds the transfer, but DNS resolution and the TLS
                // handshake happen inside the connect phase, and a resolver that
                // never answers will sit there far past any total timeout. On
                // Windows PHP cannot interrupt a blocking cURL wait either, so
                // the hang is only noticed once cURL gives up: the request then
                // dies with "Maximum execution time of 60 seconds exceeded"
                // pointing at Guzzle's handler, which is exactly what a farm
                // creation did. Capping connect bounds the worst case.
                ->connectTimeout(3)
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