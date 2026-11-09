# Website and mobile API rate limits

The Laravel server enforces limits for the admin website and both buyer and
seller app modes. Clients cannot bypass these by changing their local app.

| Traffic | Requests per minute |
| --- | ---: |
| API requests | 180 |
| Website requests | 120 |
| Writes (POST, PUT, PATCH, DELETE) | 60 |
| Login / password confirmation | 5 per email + IP, also 20 per IP |
| App registration | 3 per IP |

Authenticated requests use the account ID, so multiple tokens or devices share
the budget. Guests use the client IP. Writes share a separate budget; reads
remain available after the write budget is exhausted. Existing stricter route
limits (password reset, AI chat, reports, checkout, etc.) still apply.

Exceeded limits return HTTP 429 and a `Retry-After` header in seconds. API
requests receive Laravel's JSON error response. Clients should wait before
retrying. Limits are defined in `website/app/Providers/AppServiceProvider.php`
and attached in `website/bootstrap/app.php` and the authentication routes.

Counters use Laravel's configured cache. The current Render file cache is
suitable for its single instance; multiple instances must share a database or
Redis cache to share counters. Do not use the array or null cache in production.
The existing trusted-proxy configuration assumes access through a trusted
ingress that sanitizes forwarded client-IP headers; restrict proxies if exposing
the application server directly.

These limits cover the Laravel website/API. The separate YOLO image detector
service has its own public endpoint and is not covered by Laravel middleware.

Run the focused checks with `php artisan test --filter=RateLimitingTest` from
the `website` directory. Deployment of the changed server is required before
installed apps receive this protection; rebuilding the apps is unnecessary.
