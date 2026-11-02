# Section 1 results - October 29, 2026

Scope: Laravel backend, web dashboard and API, using the 16 rows in section 1 of FarmSpot_Vulnerability_Testing_Guide_Simplified.pdf. Section 2 was not tested. These results supersede the earlier section-1 coverage table for the checks exercised here.

Pass means the stated local synthetic checks succeeded, not that every route or deployed configuration is proven secure. Not tested means evidence is incomplete, not Pass or N/A. Application behavior was not modified.

| No. | Guide item | Result | Short notes |
| --- | --- | --- | --- |
| 1 | Login required | Pass | Guests were redirected to login on dashboard/profile/seller-request pages; protected user/farm/listing/admin/conversation APIs returned 401. |
| 2 | Role access | Pass | Buyer and farmer accounts received 403 on admin pages and seller-decision actions. Separate failure: a deactivated admin still passes the admin middleware. |
| 3 | Other users' records (IDOR) | Pass | Another farmer could not edit, delete or add photos to the dummy owner's listing; the listing remained unchanged. Public listing reads are intentional. |
| 4 | Seller approval | Pass | Buyer and farmer approve/reject requests were denied through both web and API routes. The pending farm and pin state remained unchanged. |
| 5 | Mass assignment | Pass | Added role/status/admin fields could not change profile privileges; injected listing owner/farm/availability fields were ignored while a valid update succeeded. |
| 6 | Input validation | Pass | Oversized crop name/description, invalid status/date and missing required listing fields returned 422. Quantity and price are not fields in this listing-creation endpoint; those subcases are N/A. |
| 7 | SQL injection | Pass | Quote/OR payloads in listing search/category returned no unintended records, malicious sort input did not execute, and the table remained intact. Limited request samples and source review, not exhaustive scanning. |
| 8 | CSRF | Pass | With Laravel's normal testing bypass explicitly disabled, missing and incorrect tokens on a web profile update returned 419. Protected API requests without authentication returned 401; bearer logout/replay was tested. |
| 9 | Logout | Pass | API logout deleted the bearer token; replay returned 401. Web logout controller destroyed the old synthetic session, changed its ID and logged out the web guard. Real-browser cookies and deployed session storage were not exercised. |
| 10 | Passwords | Pass | Synthetic credentials were hashed; wrong-password and unknown-email attempts returned identical generic 401 responses; model serialization hid the hash. Separate High failure: admin password change does not save its replacement. |
| 11 | Rate limiting | Fail | Twelve wrong mobile logins returned 401 without a 429. Listing creation lacks an explicit throttle. Reset throttling works for one IP locally, but forwarded IP rotation bypasses it locally; external exposure is unverified. |
| 12 | Debug mode | Not tested | Release/staging configuration and an actual error response were unavailable for verification. The deployment file says production/debug false, which alone is insufficient. |
| 13 | Secrets | Not tested | Scanned 745 tracked text files with targeted credential patterns; 112 binary/large files were skipped. No backend secret was confirmed by that scan. .env is not tracked and the example APP_KEY is empty. Cloudinary match was environment-variable construction; Android Google-services match was a client API key, whose restrictions were not verified. History, compiled client artifacts, other secret formats and deployment exposure remain unverified. |
| 14 | File upload | Pass | Listing gallery rejected wrong-type and oversized images with 422 and no photo record; accepted a valid PNG with a 201 and one record. Storage was simulated to avoid external writes; actual Cloudinary storage and malformed-image variants remain unverified. |
| 15 | Data exposure | Fail | Guest profile request returned the synthetic buyer's phone and full address. Farm-location precision and remaining response shapes were not comprehensively tested. |
| 16 | Business rules | Pass | Fourth farm denied; own-listing review denied; a second review updated one record; reports flagged at ten distinct reporters, not nine. Sequential tests only; concurrency was not exercised. Threshold signals admin review, not automatic takedown. |

## Summary

12 Pass, 2 Fail, 0 whole-item N/A, 2 Not tested. Tested-item pass rate: 12 / 14 = 85.7%. The limited coverage and open High findings mean this is not security clearance. The guide's quantity/price subcases are N/A for the reviewed listing endpoint, but the whole input-validation item applies.

Additional open High findings confirmed by the inherited observation tests: admin password update reports success but retains the previous credential; inactive administrators still pass role middleware. These are reported separately from the guide rows' narrower buyer/farmer-role and password-storage checks. Fix and retest before release. Trusting all forwarded proxies also requires deployment verification.

## Evidence

Added `website/tests/Feature/BackendChecklistTest.php`, extending the existing in-memory observation suite. Final run: **22 tests, 133 assertions, all completed successfully**, PHP 8.2.12 / PHPUnit 11.5.55. Some inherited tests deliberately assert insecure behavior, so a passing test run does not mean all checklist items passed.

Reproduce from `website`:

```powershell
& C:/xampp/php/php.exe vendor/phpunit/phpunit/phpunit tests/Feature/BackendChecklistTest.php
```

Uses minimal SQLite tables in memory, synthetic accounts and records, array sessions/cache and mocked valid-upload storage; no project migrations, real database writes or external service calls. The full feature suite and live release/staging checks were not run. Existing unrelated edits were preserved.
