# Simulated Premium activation

Implemented account-specific, server-backed Premium activation for buyers and sellers. Profile > See Premium plan > Simulate purchase grants one calendar month with no charge and no automatic renewal. An active plan is not extended by retries.

The user table stores USR_PREMIUM_STARTED_AT and USR_PREMIUM_EXPIRES_AT. USR_IS_PREMIUM is computed server-side from the end date and returned on login, registration, and GET /api/user. The app caches that account response, refreshes through the existing session check, clears premium on logout/account change, and hides Home Business shortcuts for free users. The design-only premium switch and fixed renewal date are no longer used.

Authenticated, active app users can POST /api/premium/simulate-purchase. GET /api/premium returns account and simulation availability. The purchase endpoint ignores client account IDs and dates and locks the account during activation. Premium fields cannot be granted through profile editing.

Migration: website/database/migrations/2026_10_24_000001_add_premium_access_to_user_table.php. Applied to the local database. For another server, apply the migration and set PREMIUM_SIMULATION_ENABLED=true only if demo checkout is intended. Simulation defaults off outside local/testing.

Only entitlement and simulated checkout are backed by the server in this step. Buy requests, saved farms, alerts, business verification, and sourcing screens still use their UI preview data. Buying Premium does not verify a business. No real payment or automatic billing is implemented.
