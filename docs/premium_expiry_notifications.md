# Premium expiry notifications

`premium:notify-expiry` runs hourly through the Laravel scheduler. Active accounts
receive an inbox notification and a best-effort push during the last 24 hours of
Premium, then another notice once access ends. Non-subscribers and inactive
accounts are skipped. The first run also notifies already-expired subscribers.

The unique notification key includes account, notification type, and expiry
timestamp: retries do not duplicate notices, and a renewed plan gets a fresh
notification cycle. These account notices use the ordinary notification service,
independent of optional crop/saved-farm alert settings. Device push permissions
and OneSignal configuration still apply. Tapping a notice opens Premium.

Deployment: run migrations, keep Laravel `schedule:run` running every minute,
and rebuild the mobile app for the Premium icon and tap destination. For local
Windows development, `website/scripts/premium-expiry-worker.ps1` runs the same
command hourly with a mutex preventing duplicate local workers. It must be
restarted after a computer reboot.
