# Premium alerts

## Working behavior

- Premium users choose up to 50 crops in a searchable picker, including configured aliases. Active available-now listings from any eligible public farm trigger matching crop alerts, with no saved-farm requirement or distance cutoff. New upcoming listings do not trigger crop alerts until becoming Available Now. Crop alerts have their own pause switch and retained account selections. If the same event also matches saved-farm updates, one crop alert is delivered.

- Premium active users following a public farm receive an in-app notification when that farm posts an active available-now/upcoming listing, or an existing active listing transitions to Available Now. Owners do not receive alerts for their own farms.
- New buy requests notify active sellers with matching available-now or upcoming listings on approved, visible farms. Canonical crop names and configured aliases match. Each seller receives one notification per request regardless of duplicate listings/farms; self-matches are excluded. Seller subscription is not required.
- Paused alerts and individual opt-outs are respected. Saved-farm delivery requires a future premium expiry at delivery time. Expired accounts retain their choices.
- Alert settings are accessible from Notifications and existing Business tools. Changes apply to future alerts. Existing inbox records remain.
- Saved-farm notifications open listing details. Request alerts open the seller request board with the referenced request first and labeled. A removed request is explained rather than silently opening another request.

Phone delivery is now optional and grouped; see premium_push_report.md for settings, rate limits, quiet hours, and the required worker. The Notifications inbox remains immediate. Other account/safety notifications retain their existing behavior. Backup Supplier Alerts have been removed; crop alerts cover all public farms without radius rules, alongside optional saved-farm and matching-request preferences.

## Database and API

Migration `2026_10_24_000006_create_premium_alert_settings.php` creates:
- `premium_alert_setting`: own account key, master enabled, saved-farm and buy-request preferences (default true).
- `premium_alert_delivery`: unique recipient/event hash and timestamp for atomic deduplication, cascading on account deletion.

It adds SAVED_FARM_NEW_LISTING, SAVED_FARM_AVAILABLE, BUY_REQUEST_MATCH to the existing notification enum, preserving previous types.

GET/PUT `/api/premium/alert-settings` require an authenticated active account. PUT requires boolean enabled, saved_farms, buy_requests and uses the authenticated identity only. Free accounts can manage preferences; premium eligibility is enforced during saved-farm delivery.

## Integration and reliability

Eloquent Listing and BuyRequest observers register callbacks after database commit. Rollback produces no alerts. Listing create is one event; a real status transition to Available Now is a new event. Ordinary edits and same-status saves are quiet. Harvest command uses Eloquent and triggers availability alerts. Existing historical rows and manual SQL updates do not generate alerts or backfill the inbox.

Notification creation and delivery ledger writes share a transaction. Failure rolls back the ledger and is logged, while the original listing/request remains saved. There is no automatic retry worker in this first release; failed events require replay via the service. No scheduled command or queue worker is needed for normal app-created events. The existing harvest scheduler must still run for automatic harvest transitions.

## Validation

MySQL feature tests cover settings isolation, premium expiry, master and individual opt-outs, public visibility, self-exclusion, alias matching, duplicate prevention, ordinary edits, rollback, notification-write failure, and harvest events. Flutter tests cover authenticated settings payloads, persistence, pause controls, retries/errors, free seller access, destination mapping, referenced/removed requests, and existing notification and buy-request screens.

## All-farm crop alert extension

Migration `2026_10_25_000001_add_crop_alerts.php` adds `CROP_ALERTS` and nullable JSON `ALERT_CROPS` to `premium_alert_setting`, and `CROP_AVAILABLE` to the notification type enum. The existing settings endpoints now return `crop_alerts`, `crops`, `available_crops`, and `crop_aliases`. PUT accepts up to 50 distinct catalog crops; previously saved custom crops remain valid if their stock disappears. Older clients omitting crop fields preserve selections. Premium is required to add crops; free/expired accounts may remove or clear choices, and delivery always verifies current premium entitlement.

CropCatalog shares canonical names, aliases, and publicly listed custom crops between Weekly Sourcing and Alert Settings. Crop and saved-farm selections remain separate from the weekly sourcing list. Only future listing events generate alerts; saving a crop does not backfill currently available stock. Tapping CROP_AVAILABLE opens the existing listing details screen.
