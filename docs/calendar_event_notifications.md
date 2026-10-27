# Calendar event announcements

New events on the admin dashboard have a checked **Notify farmers** option.
Uncheck it for a private event. Notes and pre-existing calendar events remain
private. Saving an event queues a single announcement; it does not loop through
farmers or contact OneSignal during the web request.

The announcement includes the event title, date/time (the calendar form's
Philippine wall time), and a summary of the details up to the inbox's 300-character
limit. The app shows a calendar icon and opens the announcement when tapped.
This sends an announcement when the event is saved, not a recurring reminder.
Edits do not send another announcement or rewrite previously delivered messages.
Deleting an event cancels delivery that has not yet started; it cannot retract
notifications already delivered.

## Delivery and resource limits

- `events:send-notifications` processes at most two batches of 100 accounts per
  run. The scheduler runs it once per minute in one background process.
- Only active seller accounts with an approved farm are selected. An account
  with multiple farms receives one copy. Accounts created after the announcement
  was queued are excluded.
- Recipient queries use a primary-key cursor and a limit. Inbox rows are bulk
  inserted; each batch makes a single push request with a 3-second connection
  timeout and a 5-second overall timeout.
- The cursor, batch recipients, and inbox rows are committed together. A crash
  cannot advance the cursor without saving the inbox notifications.
- Each batch has a one-minute claim lease and a stable UUID/idempotency key.
  Failed pushes retry the same payload after 2, 4, 8, and 16 minutes, stopping
  after five attempts. Retrying does not recreate the inbox rows.
- Without OneSignal credentials, inbox delivery still works and batches finish
  as `inbox_only`. Push errors never roll back event creation.
- Failed pushes are logged; inspect `event_notice_batch.STATE` for `failed`,
  `inbox_only`, or `sent`. `sent` means provider acceptance, not proof every phone
  displayed a push (permissions and subscriptions still apply).

Batching limits work; it is not a guarantee of zero server load. For example,
1,000 eligible farmers normally take about five scheduled runs, plus any retries.

## Running it

Apply migrations before using the event form. Production's existing `start.sh`
already runs `schedule:work`, so the new command needs no additional hosting
service. Delivery pauses while a sleeping hosting service is not running.

For local development, either keep `php artisan schedule:work` running, or use
`website/scripts/event-notification-worker.ps1`. Use one of these methods. The
PowerShell helper uses a mutex to avoid duplicate helper instances and writes
its PID to `storage/app/private/event-notification-worker.pid` and activity to
`storage/logs/event-notification-worker.log`.

For an immediate manual run: `php artisan events:send-notifications`.

Tests: `php artisan test -c phpunit.mysql.xml --filter=EventNotificationTest` uses
the dedicated `capstone_test` database and mocked push HTTP calls.
