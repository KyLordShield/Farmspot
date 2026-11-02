# Section 2 results - October 29, 2026

Scope: all six SQL database and deployment rows from FarmSpot_Vulnerability_Testing_Guide_Simplified.pdf. The main table below applies to the running local XAMPP instance and reviewed source/configuration. A subsequent authorized network retry reached Render and verified the public paths listed below. Local failures must not be represented as confirmed production exposure; hosted database privileges, logs and network restrictions remain unverified.

| No. | Guide check | Local result | Short notes |
| --- | --- | --- | --- |
| 1 | Database account | Fail | Effective Laravel config uses MySQL root with no password. A successful metadata-only connection confirmed root@localhost, ALL PRIVILEGES on *.* and WITH GRANT OPTION. This is not a limited application account. |
| 2 | Raw SQL in code | Pass | Reviewed raw query sites in app/routes use fixed expressions or bound parameters. FarmerListingController composes a query-builder subquery with toSql() and explicitly merges its bindings. SQL-like listing search/filter requests did not change query meaning or remove records. Scope is source review plus representative local tests, not proof against every injection variant. |
| 3 | Exposed files | Fail | Unauthenticated local HTTP GETs returned 200 for website/.env, a known database backup, and website/storage/logs/laravel.log. Small samples confirmed environment, SQL dump and log content; this was not a generic error page. |
| 4 | Stored sensitive data | Fail | Phone/address fields are ordinary stored profile fields and the public user-profile endpoint returns them without authorization. Retest with a synthetic buyer confirmed guest disclosure. Farm map API also returns stored latitude/longitude directly; whether that precision is justified requires a privacy/product decision. Plaintext contact storage alone is not the reason for this failure: unauthorized access is. |
| 5 | Logs | Fail | The Laravel log is downloadable without authentication locally. A harmless invalid login returned 422 and did not log its dummy password/bearer marker. A limited scan of existing logs found no matches for selected configured secrets, but that does not establish that all logs are secret-free. Public log access is sufficient to fail this row. |
| 6 | Database connection | Fail | MySQL listens on 0.0.0.0:3306; bind_address is empty. The app uses passwordless root and .env is HTTP-readable. Local PDO metadata showed no TLS on the loopback connection; lack of TLS on loopback alone is not treated as the failure. Firewall rules, remote root login and internet reachability were not tested. Source search found no DB credential match in the reviewed mobile lib/web resource/public files. |

Summary for the **local instance**: **1 Pass, 5 Fail, 0 N/A, 0 whole-item Not tested**. Pass rate: 1/6 = 16.7%. This score is scoped to local checks and does not score the unavailable deployed environment.

## Evidence and methods

- Bootstrapped Laravel configuration without printing secret values. Effective connection: MySQL, local host, root username, no password, no configured database URL. Local app environment is local with debug enabled; this does not establish release debug settings.
- Opened the configured database only to query CURRENT_USER(), SHOW GRANTS FOR CURRENT_USER, bind_address and Ssl_cipher. Grant text was converted to privilege booleans before output because raw MariaDB grant statements may contain credential hashes. No user/farm records were queried or modified.
- Local listening sockets confirmed Apache on 0.0.0.0:80 and MySQL on 0.0.0.0:3306. These listeners do not by themselves prove remote reachability through Windows Firewall or a router.
- Apache configuration has DocumentRoot C:/xampp/htdocs and permits access to that directory. Farmspot is inside that document root. The Laravel public/.htaccess does not protect sibling files requested directly through /Farmspot/website/ or /Farmspot/backups/.
- GET http://127.0.0.1/Farmspot/website/.env returned 200; a sample contained environment-key syntax. GET /Farmspot/backups/capstone_db-20261007.sql returned 200 with application/x-sql and dump syntax. GET /Farmspot/website/storage/logs/laravel.log returned 200 with text/plain and log syntax. At most 2048 bytes were sampled per response; contents and secrets were not included in outputs or copied into this report.
- GET http://127.0.0.1/Farmspot/website/public/ returned 200, confirming the local app was available during checks.
- POST /Farmspot/website/public/api/login with an invalid email and unique dummy password/token returned 422. The tracked log files grew by zero bytes; no marker was found. This exercised validation only and did not create accounts, authenticate a real account or send email.
- Scanned approximately 4.78 MB of existing local log data for selected configured secret values without printing those values. No match was found. This is a limited exact-value check, not a comprehensive log redaction audit. No conclusion is drawn about untested token/password formats or provider error bodies.
- Re-ran the SQL-like search/filter test and synthetic guest buyer-profile disclosure observation: **2 tests, 8 assertions, all completed successfully**. The disclosure test deliberately asserts insecure behavior, so successful test completion is reproduction evidence, not a security Pass.

Reproduce the isolated request checks from website:

```powershell
& C:/xampp/php/php.exe vendor/phpunit/phpunit/phpunit tests/Feature/BackendChecklistTest.php --filter 'test_07|guest_can_read_buyer'
```

## Deployed environment limitations

The initial requests were blocked by the execution environment's socket permissions. A subsequent read-only retry with authorized network access succeeded:

| Hosted path | HTTP result | Conclusion |
| --- | --- | --- |
| /up | 200 | Hosted service reachable. |
| /.env | 404 | Tested environment-file path not downloadable. |
| /storage/logs/laravel.log | 404 | Tested log-file path not downloadable. |
| /backups/capstone_db-20261007.sql | 404 | Tested backup path not downloadable. |

All tested hosted file paths returned JSON 404 responses and no sampled secret/dump/log markers. This is a Pass for those public-path checks, not proof that every possible export/backup location is protected. The local exposed-file/log findings do not apply to these tested hosted paths. Actual hosted database grants, effective connection security, firewall restrictions and log contents remain Not tested. No production user profiles were queried and no production records were changed.

The repository deployment blueprint specifies the administrative username avnadmin and a database CA path. Its actual privileges, effective TLS enforcement and service IP restrictions were not inspected. The Docker ignore file excludes local .env, SQL files, backups and logs; the container starts Laravel with its public document root. These are positive configuration observations, not deployed Pass results.

## Recommended corrections

1. Serve only Laravel's public directory and deny direct access to the project, backups and storage logs. Keep backups outside every served document root. The local server currently listens beyond loopback, so assess access restrictions promptly.
2. Replace the application's root login with a dedicated account restricted to required schema operations; handle schema administration separately. Set a password and restrict MySQL interfaces and permitted network sources.
3. Remove private buyer contacts from public responses or require explicit authorization; verify the intended farm-location precision.
4. After closing file access, assess whether exposed secrets need rotation based on who could reach the local server. This review did not rotate credentials or change settings.
5. Verify the actual hosted environment independently before assigning deployment results.

Only this report was added for section 2. No application/configuration changes, credential changes, migrations, database record changes or firewall changes were performed. The harmless invalid request could create normal server access-log entries.
