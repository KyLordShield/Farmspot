# Grouped premium phone notifications

Phone notifications are opt-in (off by default). Once enabled, grouped hourly is the default frequency. Inbox notifications remain immediate and unchanged. Phone taps use the existing OneSignal click handler to open Notifications.

## Settings

Authenticated GET/PUT /api/premium/alert-settings includes push_enabled, push_frequency (instant/hourly/daily), quiet_enabled, quiet_start, quiet_end, daily_time. All times use Asia/Manila; quiet hours default to 22:00-07:00 and daily time defaults to 09:00. Equal start/end quiet times are rejected. Legacy clients omitting push fields preserve preferences.

- Hourly: collect at least one hour of updates, then combine all eligible crops into one push. No more than one summary per rolling hour.
- Instant: delivered on the next minute worker run, grouped by crop, with a rolling one-push-per-crop-per-hour limit. Further updates wait for the next allowed send.
- Daily: one combined summary at the chosen time. Quiet hours defer it until they end. Events arriving after today's summary cutoff wait for tomorrow.
- Pausing the master switch or phone pushes clears pending phone deliveries, without deleting inbox records or replaying old updates when enabled again.
- Saved-farm and crop overlap is already deduplicated by the inbox event producer. Phone summaries additionally combine events by canonical crop and count distinct farms/requests.

## Delivery and storage

Migration 2026_10_25_000002_add_grouped_premium_push.php adds push preferences and premium_push_event / premium_push_batch tables. Events are written atomically with inbox creation. The durable batch UUID is sent as OneSignal idempotency_key on every retry; its payload remains stable. Database locking serializes a user's batch creation and sending. Only a successful response with a nonempty notification ID and no errors is recorded as accepted. This means accepted by OneSignal, not confirmed displayed by a phone.

Failed sends retry at bounded five-minute increments (at most three attempts). Events older than 24 hours are dropped from phone delivery, while inbox records stay intact. Missing configuration makes the worker skip sending. Phone delivery rechecks account status, current subscription (where required), selected crops, saved farms, listing visibility, request availability and preferences. Changed/invalid retry batches are cancelled to avoid stale or duplicated updates. Ordinary account notifications keep their existing push behavior; these controls apply only to the new Business alert types.

## Runtime

`php artisan premium:send-push` sends due batches only. It is registered in Laravel's scheduler every minute with overlap prevention. Production must invoke Laravel `schedule:run` every minute, or run its scheduler worker.

For local XAMPP development, scripts/premium-push-worker.ps1 runs only this command once per minute (without running unrelated listing jobs). Launch it hidden. A named mutex prevents duplicate local workers; its process ID is recorded at storage/app/private/premium-push-worker.pid and actionable output goes to storage/logs/premium-push-worker.log. It must be restarted after reboot; PHP and MySQL must be available. Stop the verified worker process to stop local delivery. No Windows scheduled task was installed.

Tests fake all OneSignal network traffic. Validate real delivery on a subscribed debug phone after enabling Phone notifications and Android notification permission. Hourly grouping intentionally delays the first push for an hour; Instant mode is useful for a controlled device check.

Reference: OneSignal PHP SDK notification schema documents idempotency_key and alias targeting: https://github.com/OneSignal/onesignal-php-api/blob/main/docs/Model/Notification.md
