# Laravel backend check - October 29, 2026

Scope: section 1 of the supplied FarmSpot Vulnerability Testing Guide Simplified. Section 2 (SQL database and deployment) has not been started. This is a local source review and isolated request-test retest, not a completed penetration test. Application code was not changed.

## Confirmed findings

1. **High - mobile login lacks throttling.** Twelve wrong-password requests to `/api/login` returned 401 without a 429. Login and registration routes have no explicit throttle. Add account and IP limits, then test enforcement.
2. **High - private buyer contact information is public.** A guest request to `/api/users/AUD001/profile` returned the synthetic buyer's phone and full address. Remove private fields from public responses and enforce authorization for sensitive fields.
3. **High - admin password change does not persist the replacement.** `/password` reports `password-updated`, but the old hash still matches and the replacement does not. `Auth/PasswordController.php` updates `password`; the model stores `USR_PASSWORD`. Correct the field and test login with both credentials afterward.
4. **High - deactivated administrators retain authorization at the middleware boundary.** A DEACTIVATED admin passes `EnsureUserIsAdmin`; web admin routes lack the `active` check. Require active status and verify session revocation with an existing browser session. A full browser flow was not tested.
5. **High, deployment dependent - forwarded IP rotation evades the local reset throttle.** Five invalid requests from one IP return 422, then 429; eight different forwarded IP values all return 422. The app trusts all proxies. Actual external exploitability depends on the hosting ingress and remains unverified. This does not bypass the reset code's own attempt limit.

## Section 1 checklist coverage

“Code reviewed; not tested” is not a Pass. A limited tested control does not establish a Pass for every route in its category.

| Guide check | Result / evidence |
| --- | --- |
| Login required | Limited control confirmed: guest `/api/conversations` returns 401. Other protected routes and logged-out web pages not comprehensively tested. |
| Role access | Limited control confirmed: ordinary user `/profile` returns 403. Deactivated-admin authorization fails as described above; full action matrix outstanding. |
| Other users' records (IDOR) | Code reviewed; not tested. Listing update compares the authenticated farmer with the listing owner and returns 403 on mismatch. Cross-account view/edit/upload/delete request tests outstanding. Public listing reads are intentional; private actions require separate tests. |
| Seller approval | Code reviewed; not tested. API seller approval routes require `auth:sanctum`, `active`, `admin`; web routes require `auth`, `admin`. Buyer/farmer action tests and unchanged-record assertions outstanding. |
| Mass assignment | Code reviewed; not tested. Registration assigns the role server-side; API profile updates explicitly select name, phone and address. The User model allows sensitive fields, so controller allowlists must be preserved. Injected protected-field tests outstanding. |
| Input validation | Code reviewed; not tested comprehensively. Crop name/description length, status, dates and image-size rules exist. Listing creation has no quantity/price fields; do not invent test results for them. Invalid field and error-response tests outstanding. |
| SQL injection | Code reviewed; not tested. Reviewed raw expressions use fixed SQL; no injection confirmed. Search/filter request testing outstanding. |
| CSRF | Code reviewed; not tested. Web middleware supplies CSRF protection. Normal Laravel feature tests bypass CSRF, so they cannot establish enforcement. Bearer API routes use Sanctum authentication; browser/session use needs separate verification. |
| Logout | Code reviewed; not tested. Web logout invalidates the session and regenerates the CSRF token; API logout deletes the current access token. Old-session/token replay outstanding. |
| Passwords | Limited controls confirmed: wrong API password returns generic 401; test credentials are hashed. Admin password change fails. Real stored credential review is outside this isolated run. |
| Rate limiting | Fail: login lacks limits. Reset same-IP limit works locally but forwarded IP rotation bypasses it. Reports have `throttle:10,1`; listing creation has no explicit throttle. Full sensitive-route matrix outstanding. |
| Debug mode | Not tested on staging/release. Deployment blueprint declares production and debug false; this does not verify running settings or error responses. |
| Secrets | Partial source check only. `.env` is absent from the tracked-file listing; `.env.example` is tracked. Full secret scan and repository-history/client-bundle checks outstanding. No secret values are included in this report. |
| File upload | Code reviewed; not tested. Listing/farm image validation and 5120 KB limits exist. Invalid, oversized and malformed uploads plus storage behavior outstanding. |
| Data exposure | Fail: unauthenticated buyer phone/address disclosure reproduced. Password is hidden by model serialization. Farm coordinate precision and all response shapes remain to be checked. |
| Business rules | Code reviewed; not tested. Three-farm count check exists, repeated reviews update the existing review, and report service counts distinct reporters against a configured threshold. Own-listing rating denial, concurrent farm creation and actual configured threshold need verification. |

## Reproduction and limitations

Ran from `website` using `C:/xampp/php/php.exe vendor/phpunit/phpunit/phpunit tests/Feature/SecurityAuditObservationTest.php`.

Result: **8 tests, 37 assertions, all passed**, PHP 8.2.12 / PHPUnit 11.5.55. The existing observation suite deliberately asserts insecure behavior to document it. Passing is reproduction evidence, not a security approval. It creates a minimal in-memory SQLite schema and uses synthetic records; no configured application database or external service was used by the tests.

The full feature suite, production requests, dependency advisory audit, browser session tests, complete role/ownership matrix and concurrency tests were not run. No overall section-1 pass rate is assigned because checklist rows have incomplete coverage. Existing unrelated working-tree changes were preserved.

Recommended next step: fix the confirmed High findings, replace observation assertions with secure-behavior regression tests, and complete the remaining section-1 checks before considering the backend cleared. Section 2 can then be assessed separately.
