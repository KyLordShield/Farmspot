# Saved Farms backend connection

Premium users can save/unsave a real farm with the heart on the map's selected-farm card or the farm profile. The shared account-scoped state keeps these hearts and the saved list synchronized; logout/account changes clear local state and late responses cannot populate a different account's list. Failed actions do not change the saved state.

Saved Farms now loads real farm details, current available and upcoming crop names, farm photos, profiles, and existing directions. GPS distance is best-effort and is omitted without a real fix. Sample response times, Watch switches, and the sample backup-alert entry were removed from this screen. Those alerts remain a separate future feature.

GET /api/saved-farms and PUT /api/saved-farms/{farmId} require an active, authenticated premium user. DELETE /api/saved-farms/{farmId} only deletes the signed-in user's bookmark and permits cleanup after premium ends. Expiry does not erase saved records. The composite user/farm primary key prevents duplicate saves, including retries.

Only approved, pin-active farms with active seller accounts can be newly saved. A farm that becomes unavailable remains as a redacted Farm unavailable entry that can be removed; hidden details and crops are not returned. Listings marked removed, hidden, or not available are excluded from crop summaries. Listing freshness follows the current listing-status rules; buyers are asked to confirm quantity and freshness with sellers.

Database: new saved_farm table with USR_ID, FRM_ID, SAVED_AT and a composite primary key plus cascading foreign keys. No existing listing, farm, or account status is rewritten. Applied migration 2026_10_24_000004_create_saved_farms.php locally; run it on another server before using these endpoints there.
