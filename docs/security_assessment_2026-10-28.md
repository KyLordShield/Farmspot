# FarmSpot security assessment

Assessment date: October 28, 2026 (Asia/Manila).

## Scope and conclusion

Local source review of the Laravel website/API, Flutter client, Python image detector, and deployment configuration, plus isolated Laravel request tests. The system has meaningful protections, but important gaps remain. This assessment does not establish that the deployed system is secure or that every weakness has been found.

No production requests, account changes, email sends, load tests, destructive inputs, or production database operations were performed. No application behavior was changed. Added only this report and an observational test suite. Existing unrelated working-tree changes were left alone.

Priority labels below are qualitative triage judgments, not formal CVSS scores. Runtime findings apply to the current local source; edge infrastructure may change external exploitability.

## Reproducible findings

### F1 — High: mobile login has no application rate limit

Evidence: `website/routes/api.php:29-30`, `website/app/Http/Controllers/Api/AuthController.php`, and `website/bootstrap/app.php`. Neither login nor registration has throttling; no global API limiter is configured. The controller has no failed-attempt counter. Twelve consecutive wrong passwords for the same test account/IP all returned 401, never 429.

Impact: automated password guessing and credential stuffing. Unthrottled registration also permits account creation abuse and repeated password-hashing/database work; mass account creation was not attempted.

Fix: use a shared limiter with both normalized account and IP limits for login, an IP limit for registration, and appropriate backoff. Add bounded request validation. Include tests expecting throttling after the chosen threshold. Account for shared mobile networks when choosing limits.

### F2 — High, deployment dependent: trusted forwarded IPs bypass throttling locally

Evidence: `website/bootstrap/app.php:15` trusts all proxies. Five invalid reset requests from one IP returned 422 and the sixth returned 429. Eight requests with different `X-Forwarded-For` values all returned 422 using the same underlying local request origin.

Impact: if an external client can influence the forwarded client IP accepted by Laravel, IP-based throttles and the admin login's email/IP lockout can be evaded. The reset code's own attempt counter remains a separate defense; this test did not bypass that counter or take over an account.

Fix: establish the hosting provider's actual forwarding behavior, restrict trusted proxies where possible, ensure the ingress replaces untrusted forwarding headers, and add account/user-based limits that do not depend solely on IP. Recheck through the deployed ingress. The local result does NOT prove that Render passes attacker-selected IPs through.

### F3 — High: unauthenticated access to buyer contact details

Evidence: public route `/api/users/{userId}/profile`; `website/app/Http/Controllers/Api/UserProfileController.php:78-79`. A guest request for a test buyer returned HTTP 200 with the full stored address and phone number. No relationship, consent, role, or account-status check protects those fields.

Impact: anyone who obtains a user ID can retrieve that person's contact details, including buyers. Random IDs do not replace authorization. Bulk harvesting was not attempted. Some seller contacts may intentionally be public; buyer contact disclosure needs a separate product decision.

Fix: define a minimal public profile and remove private buyer fields. Limit sensitive fields to the owner or an explicitly authorized relationship, with an opt-in policy for public seller contacts. Test guests, unrelated users, owners, admins, and deactivated accounts.

### F4 — High: admin password change silently fails

Evidence: `website/app/Http/Controllers/Auth/PasswordController.php:24` updates `password`, but the model's stored credential and allowed attribute are `USR_PASSWORD`. A request with the correct current password and valid new password returned the `password-updated` success status; the database still accepted the original password hash and did not contain the replacement hash.

Impact: an admin trying to replace a compromised password can believe the account is protected while the compromised password remains valid.

Fix: update `USR_PASSWORD` explicitly, verify the persisted credential, and define revocation of other sessions/tokens after credential changes. The regression test should require the old password to fail and new password to succeed.

### F5 — High: admin authorization does not recheck active status

Evidence: `website/routes/web.php:23` applies `auth` and `admin` without `active`; `website/app/Http/Middleware/EnsureUserIsAdmin.php:26` checks only the role. An authenticated DEACTIVATED admin passed that middleware with HTTP 200. The test also confirmed the profile route lacks `active` middleware. Deactivation code revokes API tokens but does not invalidate browser sessions.

Impact: an already authenticated administrator can retain admin authorization after deactivation. New web login checks status, but that does not cover an existing session. This finding was reproduced at the middleware boundary and verified against the route configuration; a full real-browser deactivation flow was not executed.

Fix: require active status on every authenticated admin route, including relevant authentication-management routes, and revoke browser sessions when deactivating accounts. Test an existing session across an active-to-deactivated transition.

## Additional source findings requiring targeted verification

### F6 — High: image detector lacks application abuse controls

Evidence: `ml_service/app.py:322-343` exposes `/detect` without authentication or application throttling, reads the whole uploaded file, writes it to disk before validating that it is an image, then decodes and runs inference. Clients can request inference sizes up to 2560 and enable augmentation. No upload byte cap, retention cleanup, or bounded inference queue is present in this file. The configured deployment exposes this service separately.

Impact: repeated uploads can consume disk, memory, CPU, and worker capacity. Invalid uploads are persisted before image decoding fails. Hosting/request-parser limits may impose other bounds, but were not measured. No exhaustion or large-upload testing was performed.

Fix: enforce byte and decoded pixel limits, validate before persistence, disable public tuning overrides, bound queue/concurrency, add request limits and authentication or a server-mediated access design, and remove temporary uploads promptly. A shared secret embedded in the mobile app would not be adequate access control.

### F7 — Medium: reset code consumption and attempt accounting are not atomic

Evidence: `website/app/Http/Controllers/Api/PasswordResetController.php:121-167` reads/checks the code, changes the password, then marks it consumed without a transaction or row lock. `website/app/Models/PasswordResetCode.php:131-139` writes a counter calculated from a previously read value.

Impact: concurrent requests may both pass the single-use check or overwrite one another's attempt increments. This is a source-supported race risk; concurrent exploitation was not tested. The source comment claiming consumption prevents concurrent reuse is not supported by the implementation order or locking.

Fix: lock the reset record and recheck status inside a transaction covering verification, consumption, password update, and token revocation. Serialize failures or use atomic attempt updates. Add concurrency tests against the production database engine.

The generator at `PasswordResetController.php:194` selects only 900000–999999: 100,000 candidates, not the approximately one million described by model comments. With five guesses, the chance per issued code is 1 in 20,000, not 1 in 200,000. Use the full six-digit space and preserve leading zeros, while keeping expiration and attempt limits.

### F8 — Medium: durable bearer tokens stored in ordinary preferences

Evidence: `mobile/farmspot_app/lib/services/auth_service.dart:107` stores `auth_token` using SharedPreferences. `website/config/sanctum.php:53` has no global token expiration, and login creates tokens without a per-token expiry.

Impact: extracting app storage or an applicable backup could expose a reusable session credential; tokens remain valid until explicitly revoked. This does not imply that another ordinary Android app can directly read sandboxed preferences. No installed APK, rooted-device, backup, or device-storage extraction test was performed.

Fix: use platform-backed secure credential storage; define reasonable token expiry and renewal/revocation behavior. Verify Android/iOS backup and release-build behavior separately.

## Existing protections observed

- Web login limits failed attempts by normalized email and IP, rejecting after five failures. Its effective protection depends on trustworthy IP resolution.
- Password reset routes have explicit throttles; codes are hashed, expire, have an attempt cap, and reset revokes API tokens. The same-IP reset throttle was exercised successfully.
- API protected routes require Sanctum authentication and active account status. A guest conversation request returned 401.
- Admin routes require an admin role. A signed-in general user requesting the admin profile received 403.
- Registration assigns the general-user role server-side; profile updates explicitly select permitted fields.
- Password hashes are excluded from User JSON serialization. Eloquent queries examined use bound parameters; the presence of raw SQL with fixed expressions alone is not evidence of injection.
- Farm/listing upload paths include image/MIME validation, file-size limits, and ownership checks in the reviewed code. Full malformed-file and cross-account upload testing remains outstanding.
- Admin web routes use Laravel's web middleware and CSRF protection by default. Browser CSRF enforcement was not separately exercised; Laravel normally skips CSRF validation in tests.
- Payment webhook code checks an HMAC signature and timestamp. Premium purchase simulation has a configuration gate, off by default outside local/testing.
- Release mobile API defaults use HTTPS. The deployment blueprint sets production environment and disables debug output. Actual deployed settings were not inspected.

These observations are limited positive evidence, not certifications for whole vulnerability categories.

## Test evidence and reproduction

Added `website/tests/Feature/SecurityAuditObservationTest.php`.

From `website/`, run:

```powershell
php vendor/phpunit/phpunit/phpunit tests/Feature/SecurityAuditObservationTest.php
```

Result: **8 tests, 37 assertions, all passed** on PHP 8.2.12 / PHPUnit 11.5.55.

The suite creates only minimal SQLite tables in `:memory:`, uses an in-memory cache/session, does not run project migrations, and does not contact external services. Its observation tests deliberately assert current insecure behavior to establish evidence. Passing this suite means the observations reproduced; it does NOT mean the application passed a security test. After fixing a finding, replace its observation assertions with the intended secure behavior.

## Limits and next work

- Composer dependency audit was attempted with `composer audit --locked --no-interaction --format=json`. It failed because Packagist was unreachable (curl error 7). No conclusion about dependency CVEs can be drawn. Python, Flutter, and npm advisory audits remain outstanding too.
- No production scanning, TLS/header verification, hosting-proxy inspection, installed mobile binary testing, complete authorization matrix, stored-XSS execution, SQL injection campaign, or concurrency/load testing was performed.
- The existing full feature suite was not run. Several existing feature tests require the project's MySQL schema; this assessment deliberately avoided touching configured databases.
- Fix F1–F5 first, add detector limits before exposing scans to untrusted traffic, then address reset atomicity and token lifecycle. Verify the deployed configuration and rerun security regression checks afterward.
- Before an advisor demonstration, use synthetic accounts and data, record expected versus actual responses, and present remediation plus retest evidence. Do not label this review a complete penetration test.

## Guidance used

- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html): account protection and login throttling.
- [OWASP REST Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html): endpoint access controls and request limits.
- [OWASP Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html): session lifecycle and invalidation.
