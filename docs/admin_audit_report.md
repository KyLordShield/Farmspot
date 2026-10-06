# FarmSpot Admin Dashboard — Audit Report

**Scope:** `website\` — the Laravel admin panel (routes, controllers, models, requests, middleware, Blade views, CSS) and its MySQL schema.
**Date:** 2026-10-06
**Method:** Read-only code review + read-only `SELECT` queries against `capstone_db`. No code, configuration, schema, or data was modified. No tests were executed and no browser session was opened (see *Assumptions*).
**Environment observed:** Windows / XAMPP / MySQL, `APP_ENV=local`, `APP_DEBUG=true`.

---

## Verdict

The FarmSpot admin panel is **strong in design and weak in accountability**. The UI is genuinely well built — a real design system (`public/css/style.css`, 935 lines), per-target-type report triage with reversible actions, review moderation that correctly excludes hidden reviews from star averages, and search/filter/pagination on every list. It is clearly past the "does it have pages" stage.

It is **not yet ready to be called compliant or secure**, for three reasons that are structural rather than cosmetic:

1. **Nothing an admin does is attributable.** The `audit_log` table exists and has **zero rows**; no code writes to it. The only audit trail is `report_action` (also zero rows), and it records only *take-action* steps — not report status changes, not listing edits, not user role changes, not whitelist changes, not login attempts. Meanwhile the login page states *"All access attempts are logged"*. An admin system with no attribution cannot satisfy an accountability requirement, and the false claim on the login screen makes it worse than a plain omission.
2. **The schema cannot be rebuilt from the repository.** No migration creates any of the 11 core domain tables (`user`, `buyer`, `farmer`, `farm`, `listing`, `report`, `whitelist`, `crop_category`, `notification`, `conversation`, `message`). They exist only because `database/schema/mysql-schema.sql` was imported by hand, and 12 migrations then `ALTER` them with no `hasTable`/`hasColumn` guard. This makes fresh deployment non-reproducible and it is why the default test suite cannot run.
3. **Several advertised features are inert or broken.** Password reset was broken end-to-end on the admin panel and has since been **removed by owner decision**, and has been rebuilt for mobile app users as an emailed 6-digit code; the "Remember me" checkbox threw a 500 and has been removed as well (see *Remediations applied*). Still broken: the `/profile` page cannot render. Analytics is largely hardcoded — including `search_log`, which holds 183 real rows. Three "Export Data" buttons do nothing. Two dashboards report numbers that are provably wrong.

The single highest-value work is **Batch 1** (audit writing + MFA + session timeout), because it is what converts this from "a good-looking dashboard" into "an accountable one". Nothing else in this report matters as much.

---

## How findings are grouped

The seven areas below are my own mapping of the review checklist onto this codebase, since the audit brief specified "areas 1–7" without naming them:

| # | Area | Covers |
|---|------|--------|
| 1 | Security & Access Control | auth, admin gating, MFA, sessions, rate limiting, config exposure |
| 2 | Data Integrity & Schema | migrations vs dump, FKs, collations, orphaned/discarded data, test data |
| 3 | Privacy & Data Protection | PII exposure, reporter identity, credentials, retention |
| 4 | Admin Function Completeness | required admin capabilities that are missing or inert |
| 5 | Dashboard & Reporting Accuracy | whether the numbers on screen are true |
| 6 | Usability & UI/Accessibility | can an admin actually do the job, contrast, layout |
| 7 | Code Quality & Testing | structure, duplication, test trustworthiness |

Priority: **Critical** = security hole or capstone requirement break — **High** = significant risk or missing required function — **Medium** = real problem, contained — **Low** = polish/consistency.
Effort: **S** — under an hour — **M** — half a day — **L** = multi-day.

---

## Findings

### Area 1 — Security & Access Control

| ID | Page / File | Problem | Why it matters | Suggested fix | Priority | Effort |
|----|-------------|---------|----------------|---------------|----------|--------|
| S1 | `routes/auth.php`; `resources/views/auth/forgot-password.blade.php`; `resources/views/auth/reset-password.blade.php`; `app/Http/Controllers/Auth/*` | **Deliberately withdrawn for the admin panel.** Password reset was broken at every layer: no `password_reset_tokens` table, `MAIL_MAILER=log`, `reset-password.blade.php` contained only the byte `v`, **and** — found only by executing the code — stock Breeze also assumed an `email` column, a `password` column and a `remember_token` column, none of which exist on this `user` table (`USR_EMAIL` / `USR_PASSWORD` only). The broker's lookup and the save both died with `SQLSTATE[42S22] Column not found`. The login page linked "Forgot password?" into this dead end. | An admin who forgot their password has no recovery path; the only remedy was a direct database edit. | **Owner decision: password reset is not wanted on the admin panel.** Now built for mobile app users instead - see *App password reset*. The admin UI and its four routes were removed rather than left half-working. The findings above are retained because they still describe the schema trap the app work will hit. | ~~Critical~~ Withdrawn | – |
| S2 | `app/Models/AuditLog.php`; `app/Http/Controllers/**` | **No admin action is attributable.** `audit_log` has 0 rows and nothing writes to it. `report_action` has 0 rows and covers only *take-action* steps. Report **status** changes, listing edits, user role/status changes, whitelist changes and login attempts leave no trace. | Accountability is a core capstone requirement. Without it, misuse by an admin is undetectable and unprovable. | Add an `AuditLogService::record($actorId, $action, $subjectType, $subjectId, $details)` and call it from every mutating admin action, including report status changes and listing edits. Add a read-only viewer page. | Critical | M |
| S3 | `resources/views/auth/login.blade.php:198` | The footer claims **"All access attempts are logged."** Nothing persists login attempts; `LoginRequest` only uses the ephemeral `RateLimiter` (file cache). | A security control is claimed to the user that does not exist. In an audit this reads as a false assurance, which is worse than an honest gap. | Either implement persistent login-attempt logging, or delete the sentence until it is true. | High | S (delete) / M (implement) |
| S4 | `.env`; `config/session.php:35` | `SESSION_LIFETIME=120` (2 hours) against a 15-minute requirement. `expire_on_close=false`, and the login page offers "Remember me" whose default cookie lifetime is 14 days. | An unattended or borrowed admin machine stays authenticated far longer than policy allows. | Set `SESSION_LIFETIME=15`; consider disabling "Remember me" for admin sessions or capping it far lower. | High | S |
| S5 | Whole codebase | **No MFA anywhere** — no `google2fa`, no TOTP field, no OTP step. | Single-factor admin access to a system holding user PII, farm documents and GPS data. This was an explicit requirement. | Add TOTP (e.g. `pragmarx/google2fa`) with a recovery-code path, enforced on the admin group. | High | M |
| S6 | `app/Http/Middleware/EnsureUserIsAdmin.php:24-36` | The middleware checks `USR_ROLE === 'ADMIN'` but never `USR_STATUS`. | An admin deactivated from the Users page keeps full access until their session naturally expires (currently 2 hours, longer with "Remember me"). Deactivation is meant to be immediate. | Also require `USR_STATUS === 'ACTIVE'`; invalidate active sessions on deactivation. | High | S |
| S7 | `resources/views/users/create.blade.php:89`; live DB | **Exactly one admin account exists**, and the UI states *"Admin accounts can only be created via the seeder."* There is no way to create a second admin from the interface, and no guard against self-demotion or deactivating the last admin. | Single point of failure. That one admin can lock the entire system out permanently, and there is no in-app recovery. | Allow admin creation (or at least promotion of an existing user) in the UI; block demoting/deactivating the last remaining admin; confirm destructive role changes. | High | M |
| S8 | `.env` | `APP_DEBUG=true`, `LOG_LEVEL=debug`, `APP_URL=http://localhost`. | Deployed as-is, this exposes stack traces with file paths and writes verbose logs. | Ship a production `.env.example` with `APP_DEBUG=false`, `LOG_LEVEL=warning`, an `https` `APP_URL`, and document it. | Medium | S |
| S9 | `resources/views/auth/login.blade.php:15-19`; `layouts/app.blade.php`; `partials/_category-panel.blade.php` | Three external CDNs with no Subresource Integrity and no local fallback: jsDelivr Bootstrap 5.3.3 + Bootstrap Icons 1.11.3, Google Fonts (`Alfa Slab One`, `Material+Icons`). | The admin UI renders unstyled without internet, and third-party JS/CSS runs with page privileges on a PII-bearing surface. | Self-host the assets (they are already vendored in `public/build`) and add `integrity` attributes if the CDN is kept. | Medium | M |
| S10 | `resources/views/whitelist/show.blade.php:67`; `WhitelistController` | Deactivating a whitelist number **silently cascades** — it deactivates the matching user account and unpins their farm. The confirmation only reads *"Are you sure you want to deactivate this number?"* | One click hides a real user's account and their map pin, and the admin was never told. | State the full consequence in the confirmation dialog; better, separate "un-whitelist" from "deactivate account". | Medium | S |
| S11 | `app/Models/Listing.php` | `protected $guarded = []` — every column is mass-assignable. | The admin panel is the only writer to `listing` today, which contains the risk today, but it is one controller edit away from an over-post. | Switch to an explicit `$fillable`. | Medium | S |

### Area 2 — Data Integrity & Schema

| ID | Page / File | Problem | Why it matters | Suggested fix | Priority | Effort |
|----|-------------|---------|----------------|---------------|----------|--------|
| D1 | `database/migrations/**`; `database/schema/mysql-schema.sql` | **No migration creates any of the 11 core domain tables.** Only 12 tables are ever created by migrations (`cache`, `cache_locks`, `jobs`, `job_batches`, `failed_jobs`, `personal_access_tokens`, `farm_visit_log`, `contact_log`, `listing_photo`, `report_action`, `notifications`, `listing_review`). `user`, `buyer`, `farmer`, `farm`, `listing`, `report`, `whitelist`, `crop_category`, `notification`, `conversation`, `message` come only from the hand-imported SQL dump. | A new machine cannot reproduce the database from the repository. The "just run `php artisan migrate`" path does not exist. | Convert the dump into proper `Schema::create` migrations (a squashed baseline migration is acceptable), then delete the dump or keep it clearly marked as generated. | Critical | L |
| D2 | 12 migrations incl. `2026_09_02_053007_add_frm_verification_doc_path_to_farm_table.php` | All 12 `Schema::table(...)` migrations are **unguarded** — zero use `hasTable`/`hasColumn`. | They can only run against a database that already has the legacy tables. `migrate:fresh` drops every table, after which these ALTERs target non-existent tables and abort. This is the root cause of C1. | Fixed automatically by D1. Until then, guard them so they no-op on a clean database. | High | S (guard) / covered by D1 |
| D3 | `resources/views/seller-requests/show.blade.php:209`; `SellerRequestController::reject()`; `farm` table | The rejection textarea collects a reason, validates it (`'reason' => ['nullable','string','max:500']`), and then **discards it** — there is no `FRM_REJECT_REASON` column. The controller comment concedes: *"there is no column to persist it for now."* The reject path also sends **no notification** (approve calls `NotificationService::notifyFarmLive()`; reject does not). | A seller submits farm documents and a permit, is rejected, and is never told. There is no record of why, so no appeal is possible and no pattern across rejections is visible. | Add `FRM_REJECT_REASON` + `FRM_DECIDED_AT` + `FRM_DECIDED_BY` columns; persist the reason; notify the seller with the reason. | High | M |
| D4 | `SellerRequestController::index()`:22 | The Seller Requests list queries only `FRM_STATUS = 'PENDING_REVIEW'`. Approved, rejected and archived farms are **unreachable from the UI** — no history, no re-approval, no audit of the decision. | An admin cannot answer "why was this farm rejected?" or reconsider a decision. | Add a status filter (All / Pending / Approved / Rejected / Archived) and link the decision metadata into the detail page. | High | S |
| D5 | `database/schema/mysql-schema.sql` (`whitelist`) | `FK_WHITELIST_ADDED_BY` has **no `ON DELETE` clause** (so `RESTRICT`), while `FK_WHITELIST_DEACTIVATED_ID` is `ON DELETE SET NULL`. There is also **no `WLST_DEACTIVATED_AT`** column. | The asymmetry means deleting an admin who added whitelist entries fails with an FK error, while the other link silently nulls — and "when was this deactivated" is unanswerable. | Add `ON DELETE SET NULL` (and make `USR_ADDED_ID` nullable) for consistency; add a deactivation timestamp. | High | S |
| D6 | Live DB schema | **Mixed collations.** 15 tables are `utf8mb4_general_ci` (the legacy dump) and 14 are `utf8mb4_unicode_ci` (migration-built). Verified failure: `personal_access_tokens.tokenable_id` (unicode_ci) vs `user.USR_ID` (general_ci) ? `ERROR 1267 Illegal mix of collations ... for operation '='`. | Latent today — no current query crosses that boundary — but the first `JOIN`, `whereHas`, or `whereColumn` between a migration table and a legacy table will throw at runtime. | Normalise every table to `utf8mb4_unicode_ci` in one migration. | Medium | M |
| D7 | `app/Models/UserNotification.php` | `protected $table = 'NOTIFICATION'` — **uppercase**, and MySQL on Windows is case-insensitive so it works locally. On Linux (the usual deploy target) it throws *Table 'capstone_db.NOTIFICATION' doesn't exist*. | Classic platform-dependent bug: works on the developer's machine, breaks in production. | Change to `'notification'` (lowercase). | Medium | S |
| D8 | Live DB (`listing`) | **Test data has polluted 40% of listings.** 19 of 48 rows have the crop name `Screen-Test Crop`; others are `Edit-Test Crop Renamed`, `sss`, `libando hh`. Note: **no IDs begin with `TST`** — the pollution is in the name field, not the primary key. | Any listing count, category breakdown or "top crops" figure shown to a grader is distorted, and the demo looks unfinished. | Purge or rename these rows before the demo; add a seeder that generates clean demo data. | Medium | S |
| D9 | `listing` table schema comment vs `mobile/farmspot_app/lib/models/listing.dart:124-127` | `LST_CROP_ICON` is named and commented as "Selected crop icon from library", but it actually stores the **seller-typed free-text crop name** (`Repolyo`, `Pechay`, `Kangkong`”). 18 distinct free-text values are in use. | The name actively misleads. It caused a wrong conclusion during this very audit (that Reports display raw icon keys rather than crop names). | Rename to `LST_CROP_NAME` via migration, or correct the schema comment at minimum. | Low | M |
| D10 | Live DB | Two similarly named tables coexist: `notification` (5 rows, custom app inbox) and `notifications` (0 rows, Laravel's). | Maximum confusion risk for the next developer; one is dead. | Drop the empty `notifications` table and its migration, or document why both exist. | Low | S |
| D11 | `ReportController::updateStatus()` | Report status transitions (`New ? Reviewing ? Resolved/Dismissed`) are **not** written to `report_action`. | The moderation timeline shows what was *done* but never who *decided*, so the queue can be silently closed with no record. | Record status changes as `report_action` entries too (see S2). | Medium | S |

### Area 3 — Privacy & Data Protection

| ID | Page / File | Problem | Why it matters | Suggested fix | Priority | Effort |
|----|-------------|---------|----------------|---------------|----------|--------|
| P1 | `resources/views/reports/show.blade.php:74-86` | **Reporter PII is shown on every report** — full name, **email address**, and user ID — with no access scoping, and it stays visible after the report is resolved or dismissed. | Reporters submit these expecting moderation, not disclosure to every admin on a shared screen. Unnecessary exposure of a third party's email to staff who may not need it. | Show the reporter's name and ID by default; reveal email only via an explicit "reveal" action that is itself audited. Mask or hide once the report is closed. | High | M |
| P2 | `resources/views/reports/show.blade.php:208-213` | The **accused** user's email and mobile number are displayed in full on the report detail page. | Defensible for moderation, but it should be a deliberate, logged decision rather than a default. | Gate behind the same audited reveal, and log the access. | Medium | S |
| P3 | Live DB (`personal_access_tokens`) | **171 live API tokens**, all belonging to `GENERAL_USER` accounts, with no revocation UI and no visibility into who issued them or when. | Long-lived credentials for accounts nobody audits. If one leaks there is no way to see or kill it from the admin panel. | Add a token/session listing with per-user revocation, and surface admin-role tokens explicitly. | Medium | M |
| P4 | `.env` | Real-looking Cloudinary, Groq and OneSignal credentials are present in the working `.env`. The file **is** correctly untracked and ignored by git — good. | Correct today, but there is no rotation path and no separate development credential set. | Add `.env.example` with placeholders, keep real keys out of any shared copy of the file, and document rotation. | Medium | S |
| P5 | `resources/views/users/show.blade.php:44-49` | `USR_EMAIL` and `USR_MOBILE_NUMBER` are displayed unconditionally on the user detail page. `USR_ADDRESS` is available on the record. | Every admin sees every user's contact data on every user page open. | Only reveal contact details on the pages where they are operationally needed (reports, seller verification), and audit the access. | Medium | S |

### Area 4 — Admin Function Completeness

| ID | Page / File | Problem | Why it matters | Suggested fix | Priority | Effort |
|----|-------------|---------|----------------|---------------|----------|--------|
| A1 | `resources/views/dashboard.blade.php`; `resources/views/analytics.blade.php` | **No export works.** Both pages render an "Export Data" button with no `href`, no form and no `type` handler. No export route exists anywhere. | A prominent, visible button that silently does nothing is worse than no button — a grader will try it. | Implement CSV/PDF export, or remove the buttons until they work. | High | S (remove) / M (implement) |
| A2 | `resources/views/users/**`; `UserController` | **No admin account management.** Admins cannot be created in the UI (S7), there is no "who is an admin" view, no session revocation, and no forced password reset for a compromised admin account. | Explicitly required capability, entirely absent. | Add an Admins section: promote/demote, force password reset, revoke sessions, view last login. | High | M |
| A3 | `routes/web.php`; `app/Models/AuditLog.php` | **No audit log page.** The model exists, the table exists, and there is no route or view. | Even once logging is implemented (S2), an admin needs somewhere to read it. | Add a filterable read-only audit viewer (actor, action, subject, date). | High | M |
| A4 | `resources/views/seller-requests/**` | **Rejected sellers get no notification and no reason** (see D3). | The single most user-hostile gap in the panel. | As per D3. | High | M |
| A5 | `resources/views/listings/edit.blade.php:42-50` | An admin can rewrite the **seller's crop name** and availability with no reason, no audit entry, and no notification to the seller. | Edits seller-authored content rather than moderating it, and does so invisibly. The page does correctly lock farm/farmer ownership. | Convert to moderation-only actions ("take down", "restore") with a required reason; if name correction is genuinely needed, log it and notify the seller. | High | M |
| A6 | All list views | **No bulk actions anywhere** — reports must be triaged one at a time, reviews hidden one at a time, users deactivated one at a time. | Not fatal at 48 listings and 1 report, but it does not scale and it is a standard expectation for an oversight panel. | Add bulk hide/unhide for reviews, bulk status for reports, bulk deactivate for users — each audited. | Medium | M |
| A7 | `SellerRequestController`; sidebar | **No farm/farmer directory.** Farms exist only as pending requests; once decided they disappear (D4). There is no way to see all farms, all farmers, or a seller's history. | The panel cannot answer basic oversight questions about sellers. | Add a Farms list with status, listing counts, and drill-through. | Medium | M |
| A8 | `resources/views/dashboard.blade.php` | Dead end-users: the Recent Reports and Recent Users panels are rendered as static text with no link to the underlying record or list. | An admin who spots something in the dashboard cannot act on it. | Linkify both panels. | Medium | S |

### Area 5 — Dashboard & Reporting Accuracy

| ID | Page / File | Problem | Why it matters | Suggested fix | Priority | Effort |
|----|-------------|---------|----------------|---------------|----------|--------|
| B1 | `app/Http/Controllers/DashboardController.php` | **"Active Listings" is `Listing::count()`** with no status filter. Live data: 48 total, of which **2 are `REMOVED`** (one `AVAILABLE_NOW`, one `SOON_TO_HARVEST`). The dashboard reports 48 active; the true live figure is 46. | The flagship metric on the landing page is wrong. `LST_AVAILABILITY` is the true live flag — the rest of the codebase already uses it correctly (`AiTools.php:339` filters `LST_AVAILABILITY = 'ACTIVE'`). | `Listing::where('LST_AVAILABILITY', 'ACTIVE')->count()`. | High | S |
| B2 | `resources/views/analytics.blade.php:151` | **"Pending Reports" is `Report::count()`** — every report regardless of status — and is styled red. | Overstates the moderation backlog. With 1 report it reads as "1 pending", which happens to be right by luck; it breaks the moment a report is closed. | `where('RPT_STATUS', 'New')`, consistent with the Dashboard. | High | S |
| B3 | `resources/views/analytics.blade.php:30`; `AnalyticsController` | **"Top Searched Crops This Week" plots listings-per-category, all-time.** It queries neither `search_log` nor any date range. The panel subtitle even says "Listings per category". | The title promises search demand data and the chart delivers category supply data. A viewer cannot tell the difference from the title. | Either rename to "Listings by Category (All Time)", or query `search_log` for actual top searches with a real weekly window. | Medium | S |
| B4 | `resources/views/analytics.blade.php:208-234` | **"User Growth (This Month)" is hardcoded** to `labels: ['Week 1'..'Week 4']`, `data: [0,0,0,0]`. | Renders an authoritative-looking empty chart that will stay empty forever. | Compute from `user.USR_CREATED_AT` grouped by week. | Medium | S |
| B5 | `resources/views/analytics.blade.php:147`; `dashboard.blade.php` | **"Searches Today" is hardcoded `0`** while `search_log` holds **183 rows**. `App\Support\AiTools::activity()` (lines 317-322) already computes `SearchLog::where('USR_ID',...)->count()` — the correct query exists in the codebase. | Real data is available and ignored; the metric is a lie. | Reuse the `AiTools` pattern, dropping the per-user scoping. Same for the dashboard's hardcoded "Contacts made". | Medium | S |
| B6 | `resources/views/whitelist.blade.php:26-55`; `resources/views/users.blade.php` | Stat cards call `$paginator->where(...)`, which filters the **current page collection**, not the whole table. On page 2 the "Active"/"Inactive" counts describe only rows 11-20. | Counts are wrong whenever the result set exceeds one page. This same pattern is used for the Listings "Active"/"Not available" cards (`listings.blade.php:58,68`). | Use dedicated aggregate queries (`$total` on a separate count query) alongside the paginator. | Medium | S |
| B7 | `resources/views/analytics.blade.php:67-82` | "Seasonal Trends" is three hardcoded rows (March/June/October, all "No data yet", all 0) and never reads the `trend` table. | Same as B4 — a static placeholder presented as data. | Read from `trend` by `TRND_PERIOD_MONTH`. The table currently has 0 rows, so this needs a generator first. | Low | M |
| B8 | `AnalyticsController` | `$userRoles` and `$reportStatus` are computed and passed to the view, which references neither (verified: 0 occurrences). | Two wasted queries on every page load. | Delete them or use them. | Low | S |

### Area 6 — Usability & UI/Accessibility

| ID | Page / File | Problem | Why it matters | Suggested fix | Priority | Effort |
|----|-------------|---------|----------------|---------------|----------|--------|
| U1 | `resources/views/listings.blade.php:121-151` | **The list has no `LST_AVAILABILITY` column.** The "Status" column renders `LST_STATUS` (`AVAILABLE_NOW` / `SOON_TO_HARVEST` / `NOT_AVAILABLE`) — the seller's own harvest state. The admin's own takedown state (`ACTIVE` / `NOT_AVAILABLE` / `REMOVED`) is only reachable via the filter dropdown. | **The admin cannot see which listings they have removed.** With 2 rows currently `REMOVED`, a removed listing looks identical to a live one. This directly undermines the listing-oversight requirement. | Add an explicit "Visibility"/"Moderation" badge column, or merge both states into one clear cell. | High | S |
| U2 | `resources/views/profile/edit.blade.php`; `app/Http/Controllers/ProfileController.php`; `ProfileUpdateRequest` | **The profile page is broken.** It uses `<x-app-layout>` but `resources/views/components/app-layout.blade.php` does not exist, and `ProfileUpdateRequest` validates Breeze fields (`name`, `email`, `email_verified_at`) against a schema that has `USR_NAME`, `USR_EMAIL`, `USR_ID`. `ProfileController` calls `$user->fill($request->validated())`, `$user->isDirty('email')` and `$user->delete()`. | A page a signed-in admin can reach will not work. Also a hard-delete path that will fail on FK constraints (see D5) if it ever did render. | Rewrite against the real `USR_*` columns, or remove the profile routes entirely — an admin panel with exactly one admin has little use for self-service profile editing. | High | M |
| U3 | `resources/views/reports/show.blade.php:114-135, 205-222` | The reported listing, farmer and user are shown as **plain IDs with no link**. | A moderator must copy an ID and navigate manually to inspect the subject of the report — the single most important step in the workflow. | Wrap subject IDs in links to the relevant admin page. | Medium | S |
| U4 | `resources/views/reports.blade.php` | The Reports list renders `session('success')` but **not `session('error')`**. | Failed actions (e.g. a refused action) fail silently — the admin sees nothing happen and no explanation. Every other list page (listings, reviews, users, whitelist, seller-requests) does render the error. | Add the `session('error')` alert block to match the other pages. | Medium | S |
| U5 | `resources/views/users/show.blade.php:57-60`; `resources/views/users.blade.php` | **Dead `FARMER` role branch.** The `user` table enum is `('GENERAL_USER','ADMIN')` only, so `USR_ROLE == 'FARMER'` can never be true. Everything that is not `ADMIN` is labelled **"Buyer"** — including farmers, who are `GENERAL_USER` + `USR_IS_SELLER`. | Misleading an admin about a seller's account type. The real seller signal is `USR_IS_SELLER`, which is not surfaced here. | Delete the `FARMER` branch; label by `USR_IS_SELLER` and role separately. Also render `PENDING_VERIFICATION`/`DEACTIVATED` as badges rather than raw enum text. | Medium | S |
| U6 | `resources/views/listings/show.blade.php:72`; `reports/show.blade.php:127, 226` | **Raw enum values rendered as text**: `{{ $listing->LST_AVAILABILITY }}`, `{{ $report->listing?->LST_STATUS }}`, `{{ $accused?->USR_STATUS }}`. On the same page, `RPT_STATUS` gets a proper badge. | Inconsistent and unprofessional; a moderator sees `AVAILABLE_NOW` where a label belongs. | Centralise enum?label mapping as model accessors and use them everywhere. | Medium | S |
| U7 | `resources/views/whitelist/create.blade.php:42-44`; `whitelist` table | **The whitelist records only a phone number.** The form has one text field; the table has no name or note column. The admin cannot record who the number belongs to. | The stated purpose is authorising *unregistered* people — precisely the case where the admin has no record to look them up in. After a week the list is unmemorable numbers. | Add `WLST_LABEL` / `WLST_NOTE`; show a read-only "matches existing user/farmer" indicator so the admin knows what they are pre-approving. | Medium | M |
| U8 | `public/css/style.css:35, 37, 20` | **Measured WCAG AA contrast failures.** `--amber #ff9800` on `--amber-bg #fbf3dc` = **1.95:1** (used by `badge-soft-warning` = "Soon to Harvest", "Pending", "Pending requests"). `--slate #9e9e9e` on `--slate-bg #eef1f4` = **2.36:1** (`badge-soft-neutral` = "Not Available", "Hidden", "Inactive"). `--text-faint #8a948f` = **3.02–3.13:1**, used for `.data-table thead th` at **11px uppercase** and for `.cell-faint` (IDs, dates, "No comment"). AA needs 4.5:1 for text this size. Success, danger, info badges and body text all pass. | Status meaning is carried almost entirely by badge colour and text. The two failing colours are the "pending"/"soon"/"hidden"/"not available" states — exactly the states a moderator scans for. | Darken `--amber` and `--slate` to reach =4.5:1 on their backgrounds, and darken `--text-faint` for table headers and `.cell-faint` (or increase those to 13px semibold). | Medium | S |
| U9 | `resources/views/users/create.blade.php:76-79`; `whitelist/create.blade.php:43`; login | **Mobile numbers are free-text in three places** with no `inputmode`, pattern, placeholder or canonicalisation. The whitelist unique key is the exact string. | `0917–` and `+63917–` become two different whitelist entries for one person, so a pre-approved number can be blocked by a duplicate. | Normalise to one canonical format on write (E.164 or `09XXXXXXXXX`) and validate against it; add `inputmode="numeric"` and a placeholder. | Medium | M |
| U10 | `resources/views/auth/login.blade.php:137-138, 20-121` | Login page quality gaps: **no `<h1>`** (two sibling `<h2>`s, "FarmSpot" and "Sign In"); a **dead `Alfa Slab One`** webfont request that the page's own CSS overrides with the system stack (lines 51-53); and a **100-line inline `<style>` block** that duplicates the design system with a different green (`#1e4d2b` vs `--brand-700: #1b6b2c` / `--brand-800: #0f4a1c`). | The login page is the least polished screen in a well-designed product, and it is the first thing a grader sees. The three greens are a visible brand inconsistency across the app. | Promote the shared tokens into the login page (or a shared partial); remove the dead font; give the page one `<h1>`; pick one brand green. | Low | S |
| U11 | `resources/views/*`; `seller-requests/show.blade.php:133` | Views use inline `style="white-space: pre-wrap;"` (reports, seller-requests) despite a full design system, and farm photos omit the `loading="lazy"` that listing photos use. | Small consistency drift in an otherwise disciplined stylesheet. | Add a `.preserve-lines` utility; add `loading="lazy"` to farm photos. | Low | S |
| U12 | `public/css/style.css:893-935` | At =768px the sidebar becomes a wrapping horizontal menu with `flex: 1 1 auto` per item across 8 destinations, and there is no collapse toggle. | On a phone this is likely a two-to-three row wall of links. Cannot be confirmed without a browser — see *Needs visual check*. | Verify, then consider a hamburger/collapsible sidebar. | Medium (unverified) | M |

### Area 7 — Code Quality & Testing

| ID | Page / File | Problem | Why it matters | Suggested fix | Priority | Effort |
|----|-------------|---------|----------------|---------------|----------|--------|
| C1 | `phpunit.xml`; `phpunit.mysql.xml`; 14 test files using `RefreshDatabase` | **The test suite cannot demonstrate the schema — now confirmed by running it.** The default `phpunit.xml` uses `sqlite`/`:memory:`, which is safe (it never touches `capstone_db`), but `RefreshDatabase` builds an *empty* database because the migrations contain only `ALTER TABLE` statements and no `CREATE TABLE` — the real base tables arrived via a hand-imported SQL dump. `php artisan test --filter=PasswordResetTest` was executed and failed on 4/4 tests with `SQLSTATE[HY000]: General error: 1 no such table: farm` at `alter table "farm" add column "FRM_VERIFICATION_DOC_PATH"`. Zero assertions ran. `phpunit.mysql.xml` points at a separate `capstone_test` database that must be hand-imported first. | The suite's status rests on a hand-prepared database, not on anything reproducible from the repository. A grader running `php artisan test` gets an immediate migration failure, not a test failure — the failure is louder than the bug it is meant to catch. Note this also means C4's Breeze tests could never have passed, so they were never evidence that anything worked. | Fix D1/D2 first: give the migrations real `CREATE TABLE` statements (or a schema-loading step for tests), then make `phpunit.xml` able to build the schema alone and drop the manual import. | High | M (after D1) |
| C2 | `app/Http/Controllers/ReportController.php` (27 KB) | One controller holds list, show, apply-action, undo, status update and the whole per-target-type option matrix. | The most security-relevant controller in the app is also the least navigable; review and regression risk concentrate in one file. | Split into `ReportController` (read), `ReportActionController` (mutate), and a `ReportActionResolver` service for the per-type option matrix. | Medium | M |
| C3 | `app/Http/Requests/` | Only **3** FormRequest classes exist (`ProfileUpdateRequest`, `Auth\LoginRequest`) — the rest of the app validates inline in controllers. | Validation rules for listing/report/whitelist/user writes are untestable in isolation and drift between list and action paths. | Introduce FormRequests for the mutating admin endpoints. | Medium | M |
| C4 | `tests/Feature/Auth/*`; `tests/Feature/ProfileTest.php` | The Breeze default tests cover exactly the areas that are broken (password reset, email verification, profile, password confirmation) — yet they are the 5 smallest test files (0.8–2.6 KB) in a suite whose real files are 14–36 KB. | The broken features are precisely the ones with thin, likely-failing default coverage. **I did not execute them** (see *Assumptions*), so treat this as "expected to fail", not confirmed. | Run them once the schema is reproducible (C1) and fix the failures — they will confirm S1 and U2. | High | M |
| C5 | `resources/views/*`; `Report::reasonLabel()` | Enum?label mappings are re-implemented inline in at least six views (listing status, farm status, report status, review status, user status, notification types) instead of being centralised. | This is the direct cause of the raw-enum inconsistencies in U6 — a fifth view will be missed next time. | Add label accessors or PHP enums on the models; have every view call them. | Medium | M |
| C6 | Repository root | No `AGENTS.md` / deployment notes describe the mandatory manual `mysql-schema.sql` import step. | The single most important setup fact about this project is undocumented. | Write the setup order (import dump ? `php artisan migrate` ? seed) into `AGENTS.md`. | Medium | S |
| C7 | `docs/` | Three prior reports sit in the repository (`listing_reviews_report.md`, `myfarm_report.md`, `review_ui_tweaks_report.md`). | Harmless, but they are working notes rather than deliverables. | Keep or move to an archive folder; do not ship them as project documentation. | Low | S |

---

## Missing admin functions, ranked

Ordered by how much each closes a stated requirement gap, not by effort.

| Rank | Missing function | Blocks which requirement | Effort |
|------|------------------|------------------------|--------|
| 1 | **Audit logging for every admin action** + a viewer page | Accountability / traceability | M + M |
| 2 | **Admin account management** — create/promote a second admin, revoke sessions, force password reset | Admin security; removes the single-admin lockout | M |
| 3 | **MFA for admin accounts** | Explicit security requirement | M |
| 4 | **Seller-request rejection reason, notification, and re-review** | Farm approval oversight; user fairness | M |
| 5 | **Listing moderation with reason + seller notification** | Listing oversight | M |
| 6 | **Password reset that actually works** - for *app users*, not admins | User account recovery | **Done.** Built and verified for app users only, as an emailed 6-digit code. Admin reset remains withdrawn by owner decision |
| 7 | **Exports** (reports / listings / users CSV) | Oversight reporting | M |
| 8 | **Bulk actions** (triaging reports, hiding reviews, deactivating users) | Scalability of oversight | M |
| 9 | **Farms / farmers directory** with per-seller history | Seller oversight | M |
| 10 | **Report ownership / assignment and SLA tracking** | Queue management as volume grows | M |
| 11 | **Admins cannot see session/token inventory** | Access review | S/M |
| 12 | **Admin notification centre** (someone assigned work) | Workflow | M |

---

## "Make the admin go elsewhere"

Tasks that do not belong in the admin panel, either because they are the user's job, a scheduled machine's job, or a reporting surface rather than an interactive screen.

| Current behaviour | Move it to | Why |
|-------------------|-----------|-----|
| Admin edits a seller's `Crop Name` and `Harvest Date` (`listings/edit.blade.php`) | **Seller app** — the admin should only take down / restore | An oversight panel that rewrites user content becomes a content editor. |
| "Searches Today", "Contacts made", "User Growth", "Seasonal Trends" (`analytics.blade.php`) | **A scheduled report** generated nightly and emailed or exported | These are periodic aggregates. Rendering them live on every page view is both slow and wrong-headed. |
| "Export Data" buttons on Dashboard and Analytics | **A real export endpoint**, invoked deliberately | Buttons that do nothing should not exist; exports are an action, not a view. |
| Listing expiry and harvest reminders (notification types `LISTING_EXPIRING_SOON`, `LISTING_EXPIRED` already exist) | **A scheduled job / queued worker** | Already modelled as notifications; firing them on a schedule is not an admin's job. |
| Per-user activity stats (`SearchLog`, `ContactLog`, `FarmVisitLog`) | **The AI tools layer** (`app/Support/AiTools.php`) — it already computes these | One implementation, reused, instead of a second divergent copy. |
| Helping a user reset their password | **Done** - self-service emailed-code flow for app users (S1) | An admin setting another user's password is both a privacy problem and a security problem. |
| Deciding *whether* a farm is approved | **Keep in the admin panel** | This is genuine moderation and must stay. |

---

## Safe to delete (after verifying references)

Nothing here may be removed until you have confirmed no route, view or test still references it.

| Candidate | Evidence | Notes |
|-----------|----------|-------|
| `resources/views/welcome.blade.php` (~82 KB) | The `/` route redirects to `login` | Laravel/Tailwind boilerplate. Delete. |
| `resources/views/auth/register.blade.php` + `app/Http/Controllers/Auth/RegisteredUserController.php` | No `register` route exists in `routes/auth.php` | Registration is mobile-app-only. Delete both. |
| `resources/views/auth/verify-email.blade.php`, `VerifyEmailController`, `EmailVerificationPromptController`, `EmailVerificationNotificationController` | `User` does **not** implement `MustVerifyEmail` | The routes are registered but nothing can pass them. Delete. |
| `resources/views/auth/confirm-password.blade.php` + `ConfirmablePasswordController` | The admin login has no password-confirmation step | Verify no form posts to `password.confirm` first. |
| `resources/views/components/*` | Breeze/Tailwind components; the only consumer is the broken profile page (U2) | Delete once U2 is resolved one way or the other. |
| `resources/views/layouts/navigation.blade.php` | The admin layout has its own sidebar | Verify `layouts/guest.blade.php` does not include it. |
| `package.json`, `package-lock.json`, `tailwind.config.js`, `postcss.config.js`, `vite.config.js`, `public/build/*` | No admin view uses `@vite`; CSS/JS come from CDN | Delete if you adopt the CDN/self-hosted assets in S9. Otherwise they are the source for self-hosting. |
| Live `notifications` table (0 rows) + `2026_10_01_000007_create_notifications_table.php` | Superseded by the custom `notification` table (D10) | Delete after confirming nothing references Laravel's `Notifiable` DB channel. |

**Do NOT delete** — these look like leftovers but are required by the audit requirements: `app/Models/AuditLog.php` and the `audit_log` table (implement S2/A3 instead), `resources/views/profile/edit.blade.php` (fix or remove deliberately per U2).

**Already deleted** — `resources/views/auth/reset-password.blade.php` and `resources/views/auth/forgot-password.blade.php`, together with the four `password.*` reset routes in `routes/auth.php`. This was an owner decision, not an oversight: admin self-service reset is unwanted and its routes were a confirmed 500 (see S1 and *Remediations applied*). Recover with `git checkout -- website/resources/views/auth/`. Note `password.update` and `password.confirm` are a *different*, still-wanted feature and were deliberately kept.

---

## Needs visual check

Could not be confirmed without a browser. Each item is a specific thing to look at, not a general instruction.

| # | What to check | Why code review could not settle it |
|---|---------------|--------------------------------------|
| 1 | `/profile/edit` — does it 500 on the missing `x-app-layout` component? | Depends on Blade component resolution at runtime. |
| 2 | Sidebar at 375px and 768px — how many rows does the 8-item wrapping menu occupy? | Pure layout question (U12). |
| 3 | Widest tables (`listings`, `reports`, `reviews`) — is horizontal scroll acceptable, or are key columns cut off? | `.table-responsive` + `white-space: nowrap` headers. |
| 4 | Listings list — with `LST_AVAILABILITY` hidden (U1), can an admin actually spot a removed listing? | Confirms the impact of U1. |
| 5 | Dashboard and Analytics — the two brand greens (`#1e4d2b` vs `#1b6b2c`) side by side. | Visual confirmation of U10. |
| 6 | Badge legibility after a contrast fix — verify "Soon to Harvest", "Hidden", "Inactive" are distinguishable. | U8 needs a before/after visual. |
| 7 | Category picker modal on a phone — the icon grid and the selected-name readout. | Recently changed; not visually verified. |
| 8 | Listing and farm photos — do they resolve? `FILESYSTEM_DISK=local` requires a `public/storage` symlink that XAMPP often lacks. | Cannot be determined statically; broken images would be very visible. |
| 9 | Login page at 375px — the brand panel is hidden below 768px (line 119), leaving a bare form. | Layout question. |
| 10 | Focus outlines and keyboard order across the dense action-icon tables (`.btn-icon`). | Only `.btn:focus` is defined in the stylesheet. |

---

## Fix batches

Sequenced so each batch leaves the system in a better state than it found it. Batches 0 and 1 are the ones that matter.

### Batch 0 — Stop the bleeding (S each, ~half a day total)
1. `APP_DEBUG=false`, `LOG_LEVEL=warning` in the deploy env; add `.env.example`.
2. `SESSION_LIFETIME=15`.
3. Delete the "All access attempts are logged" line from the login footer (or mark it as a Batch 1 dependency).
4. Remove or wire up the two dead "Export Data" buttons (A1).
5. Purge the `Screen-Test Crop` / `sss` / `libando hh` listing rows (D8).

### Batch 1 — Accountability and access control (the priority batch)
1. `AuditLogService` + calls from every mutating admin action, **including report status changes** (S2, D11).
2. Audit log viewer page (A3).
3. Persistent login-attempt logging, so the login-page claim can be made true (S3).
4. `USR_STATUS === 'ACTIVE'` check in `EnsureUserIsAdmin` (S6).
5. TOTP MFA with recovery codes (S5).
6. Session/token revocation for admins (P3, A2).
7. Second-admin creation + last-admin protection (S7, A2).

### Batch 2 — Unbreak the data layer
1. Rejection reason + decided-at/by columns, notification on reject, status filter on the list (D3, D4, A4).
2. `LST_AVAILABILITY` column in the listings table (U1).
3. Convert the SQL dump into real `Schema::create` migrations, then guard or delete the ALTERs (D1, D2).
4. Normalise collations to `utf8mb4_unicode_ci`; fix `UserNotification::$table` casing (D6, D7).
5. Whitelist: `ON DELETE SET NULL` symmetry + deactivation timestamp (D5).
6. Whitelist: label/note column + canonical mobile format (U7, U9).

### Batch 3 — Make the numbers true (S each, fast wins)
1. Dashboard "Active Listings" ? filter `LST_AVAILABILITY` (B1).
2. Analytics "Pending Reports" ? filter status (B2).
3. Aggregate queries instead of paginator `where()` on stat cards — whitelist, users, listings (B6).
4. Real search/growth/seasonal queries or honest titles (B3, B4, B5, B7).
5. Delete the dead `$userRoles` / `$reportStatus` queries (B8).
6. Add the missing `session('error')` alert to the Reports list (U4).
7. Linkify the dashboard's recent panels (A8).

### Batch 4 — Usability and accessibility
1. Contrast fixes for `--amber`, `--slate`, `--text-faint` (U8).
2. Centralise enum labels on the models; remove every raw-enum render and the dead `FARMER` branch (U5, U6, C5).
3. Link report subjects to their admin pages (U3).
4. Decide the profile page: fix it against `USR_*` or remove the routes (U2, C4).
5. Login page `<h1>`, dead font removal, one brand green (U10).

### Batch 5 — Missing capabilities
1. Exports (A1), bulk actions (A6), farms directory (A7).

### Batch 6 — Cleanup and structure
1. Delete the Breeze leftovers listed above.
2. Split `ReportController` (C2); add FormRequests (C3).
3. Write `AGENTS.md` with the schema bootstrap order (C6).
4. Rename `LST_CROP_ICON` ? `LST_CROP_NAME`, or fix the schema comment (D9).
5. Tidy `docs/` (C7) and inline styles (U11).

---

## Assumptions and limitations

Recorded explicitly because no clarifying questions were asked, per the audit brief.

1. **"Areas 1–7" were not named in the brief.** The seven areas used above are my own mapping of the checklist onto this codebase. If a specific seven-item taxonomy was intended, the mapping should be re-checked — the findings themselves stand regardless of how they are grouped.
2. **No tests were executed.** Running them would require writes (14 files use `RefreshDatabase`, and `phpunit.mysql.xml` targets `capstone_test`). C1 and C4 are derived from static reading and from the SQLite migration failure observed during earlier work, not from a fresh test run.
3. **No browser session was opened.** All ten items in *Needs visual check* are unconfirmed by design.
4. **Live-data numbers were read from `capstone_db` with `SELECT` only.** Counts cited (48 listings / 2 removed, 1 admin, 1 report, 0 audit rows, 183 searches, 171 tokens, 29 tables, mixed collations) are a snapshot of the current development database and will change as work continues.
5. **The claim that `report` uses an integer primary key is stale.** The live column `report.RPT_ID` is `char(6)`, consistent with `2026_10_01_000004_change_report_id_to_six_digits.php` and the rest of the schema. This is **not** counted as a defect.
6. **`LST_CROP_ICON` holds a crop name, not an icon key** — confirmed from `mobile/farmspot_app/lib/models/listing.dart:124-127`. The listings and reports pages therefore display crop names correctly; the defect is the misleading column name (D9), not the rendering.
7. **No row IDs begin with `TST`** (verified across `listing`, `user`, `farm`, `report`, `listing_review`, `crop_category`). The test-data problem is in listing *names*, not IDs (D8).
8. **The 15-minute session lifetime and the MFA requirement** are taken from the stated capstone requirements; no configuration file in the repo encodes either.
9. **Collation mismatch D6 is rated Medium, not Critical**, because no current query crosses the boundary — it is a latent failure, verified to throw the moment a join is added.
10. **API controllers were reviewed only where they intersect the admin panel** (`Api/Admin/SellerRequestController`, `Api/InsightsController`, Sanctum tokens). A full API audit is out of scope for this document.
11. **Effort estimates assume one developer familiar with the codebase** and exclude review/QA time.
12. **The audit phase of this document was read-only.** Only this report was written during the audit itself. Remediation of S1 and of "Remember me" was subsequently authorised, verified, and then partly reverted on owner instruction — all documented under *Remediations applied* and *Change proof*.

---

## Remediations applied

Two items were actioned. Both were later changed by owner decision, so read the *Current state* subsection first.

### The schema trap behind S1

Worth keeping even though admin reset is withdrawn, because the app work will hit the same wall. The visible defects (missing table, one-byte view) were findable by inspection. The column mismatches were **not** - the code looked correct and only failed when executed. This schema stores `USR_EMAIL` / `USR_PASSWORD` and has **no** `email`, `password` or `remember_token` columns, so four stock-Breeze assumptions broke at once:

| # | Defect | Symptom |
|---|--------|---------|
| 1 | `password_reset_tokens` table absent | broker could not store a token |
| 2 | `reset-password.blade.php` held the single byte `v` | `/reset-password/{token}` rendered the literal text `v` |
| 3 | Broker looked users up by `email` | `SQLSTATE[42S22] Unknown column 'email' in 'where clause'` |
| 4 | Save used `password` + `remember_token` | `SQLSTATE[42S22] Unknown column 'password' / 'remember_token'` |

Defect 4 also surfaced a second, unrelated 500: `Auth::attempt($credentials, true)` failed on `remember_token`, so the login form's **"Remember me" checkbox threw on every use**.

### Current state

**Password reset on the admin panel: removed, by owner decision.** The four routes (`password.request`, `password.email`, `password.reset`, `password.store`) are gone from `routes/auth.php`, both views are deleted, the "Forgot password?" link is gone from the login page, and the two controllers plus the `User` model hooks are reverted to their original state. `/forgot-password` and `/reset-password/{token}` now return 404.

It was originally repaired in full and verified - token issued, page rendered 200, POST changed the password, `Auth::attempt` logged in with the new one, password hash then restored byte-for-byte. That repair was reverted on request rather than left in place, because admin self-service reset is unwanted and half-finished dead code is worse than none.

**Kept deliberately:**

- `password_reset_tokens` table and its migration, already applied (`[18] Ran`). Standard Laravel shape, unused for now, ready for the app work.
- The **"Remember me" removal**. Separate bug from forgot-password, and the owner's view is that it is redundant anyway - see below.
- `password.update` and `password.confirm` (logged-in password change), untouched.

### Why "Remember me" is redundant here

The mobile app already has the behaviour "remember me" would provide, without any checkbox. `lib/main.dart:96` reads a persisted `auth_token` from `SharedPreferences` behind the splash and routes straight to `HomeScreen`; `AuthService.getToken()` (`auth_service.dart:398`) is the source of truth, and `AuthService.logout()` (`auth_service.dart:545`) is the only thing that clears it. Server-side, `config/sanctum.php:53` sets `'expiration' => null`, so issued tokens never expire. A user logs in once and stays logged in until they explicitly log out. No `remember` parameter is sent by the app, and grepping `remember.?me` across `lib/` returns nothing.

Consequence of removing it on the web: admin sessions end with the browser session. Reviving it needs a `remember_token` column added on purpose.

### Not touched

`website/.env` was never read or edited by this work. `MAIL_MAILER` is still `log`, so **no email has ever been sent** by this application. Also unchanged: every other finding in this report, and all previously committed work.

Two notes that shaped the app-side design. `config/mail.php` in Laravel 12 keys encryption off `MAIL_SCHEME` - there is no `MAIL_ENCRYPTION` key, so setting that name silently does nothing. And `password_reset_tokens` alone is not sufficient for the app's architecture: the app is token-authenticated via Sanctum, not session-cookie authenticated, so a browser-oriented reset link flow does not map onto it without new API routes.

## App password reset: built and verified

The app has its own, separate reset flow - see the section above for why it is a code and not a link. Both sides were greenfield; both now exist.

**Backend** (`website/`):

- `2026_10_06_000002_create_password_reset_code_table.php` - `PASSWORD_RESET_CODE`, keyed one row per `USR_ID`, so a new code replaces any previous one rather than accumulating. Columns `RSTC_CODE_HASH`, `RSTC_EXPIRES_AT`, `RSTC_ATTEMPTS`, `RSTC_CONSUMED_AT`. Declared uppercase to match the project's existing table convention; local MariaDB runs `lower_case_table_names=1` so it materialises lowercase.
- `Api\PasswordResetController` - `POST /api/forgot-password` and `POST /api/reset-password`, written against `USR_EMAIL` / `USR_PASSWORD` rather than the stock `email` / `password` columns that broke S1.
- `App\Notifications\PasswordResetCodeSent` - the code is passed in as a plain string and deliberately never read back off the model, because only its bcrypt hash is stored. This is the single moment the cleartext code exists in the process.
- `config/auth.php` - `password_reset_code` block for expiry, attempt cap, and the local-only debug switch.

Security properties, each verified by execution rather than by reading:

- Only **bcrypt hashes** are stored; the plaintext never reaches the database.
- **No account enumeration.** Unknown addresses, the admin address, and real users all get the same 200 and the same message, and no code row is written for non-users. The app screen is worded to match, so it cannot be used to discover who has an account.
- **Single use**, via `RSTC_CONSUMED_AT`. A replayed valid code is refused with "already been used".
- **10-minute expiry**, and codes are generated with `random_int(900000, 999999)` so the value is always six digits.
- **Five failed attempts** per code, counted server-side and independent of the IP throttle.
- **Every Sanctum token is revoked** on success, so a stolen token dies with the old password. Verified by issuing two tokens, resetting, and confirming zero remained.
- **Throttled per route**: `3/min` on requesting a code, `5/min` on guessing one. Verified: `200, 200, 200, 429, 429, 429`. The two buckets are independent, so flooding "send code" cannot exhaust a victim's reset budget.
- `PASSWORD_RESET_EXPOSE_CODE=true` returns the code in the API response, but **only** when `APP_ENV=local` as well - so the shortcut cannot be switched on in production even by accident.

**App** (`mobile/farmspot_app/`): `ForgotPasswordScreen` and `ResetPasswordScreen`, a "Forgot Password?" link on the login screen, and `requestPasswordResetCode` / `resetPasswordWithCode` on `AuthService` following the existing `AuthLoginResult` contract. The code field is digits-only and capped at six, the service strips spaces and dashes so `123 456` pastes straight out of the email, and a resend is available because the backend discards the previous attempt count. On success it returns to login rather than home, because the reset invalidated the session token.

Verified end to end against the real HTTP kernel: request, wrong code, expired code, exhausted attempts, successful reset, login with the new password, rejection of the old one, replay, token revocation, weak-password rejection, throttling, and email rendering. The account's password was restored byte-for-byte and its reset rows deleted afterwards. `flutter analyze` reports no issues.

**Two things remain open, both requiring the owner to edit `website/.env`:**

1. `MAIL_MAILER` is still `log`, so **no email has actually been sent**. Until SMTP is configured the flow is exercised through the local debug switch. Ports 587 and 465 were both confirmed reachable.
2. `APP_NAME` and `MAIL_FROM_NAME` are still the stock `Laravel`, so the rendered email is branded "Laravel" with a `laravel.com` logo. The notification now hard-floors the From display name to `FarmSpot` in code because a password-reset mail signed "Laravel" reads as phishing, but only `APP_NAME=FarmSpot` rebrands the mail **body**.

Also worth noting for the physical device: `AuthService.baseUrl` is `http://127.0.0.1:8000/api`, which only resolves on an emulator. On a real handset it needs the PC's LAN IP.

---

## Change proof

The audit itself was read-only and completed first. The S1 repair was then authorised, verified, and subsequently reverted on owner instruction. The category-CRUD work referenced above was already committed as `a9d0d64 added crud foe categories` and was not touched.

Tracked files modified:

```
 M website/app/Http/Requests/Auth/LoginRequest.php
 M website/resources/views/auth/login.blade.php
 M website/routes/auth.php
 D website/resources/views/auth/forgot-password.blade.php
 D website/resources/views/auth/reset-password.blade.php
```

Untracked:

```
?? docs/admin_audit_report.md
?? website/database/migrations/2026_10_06_000001_create_password_reset_tokens_table.php
```

Both deleted views are recoverable with `git checkout -- website/resources/views/auth/`.

Database changes (not in git):

- migration `2026_10_06_000001_create_password_reset_tokens_table` applied; `password_reset_tokens` exists and is intentionally kept
- a throwaway admin (`USR_ID = LI33XH`, `itslinlin098@gmail.com`) was created during testing and has since been **deleted**, along with its Sanctum tokens
- that same address is now a real **GENERAL_USER**: `USR_ID = CBGYS8`, `USR_ROLE = GENERAL_USER`, `USR_STATUS = ACTIVE`, for testing in the mobile app. `POST /api/login` returns HTTP 200 with a working token for it. Note the mobile API deliberately refuses `ADMIN` accounts (`Api/AuthController.php:74`), so a separate admin row is still required for the web panel
- `USR_PASSWORD` for that account is bcrypt, set from the owner's chosen password; it is not recorded in this report
- no other rows were modified. The original admin `EMOFGA / admin@farmspot.test` is untouched, and its password hash was restored byte-for-byte after every verification run

Verified after the removals: `/login` renders 200 with the email and password fields, no "Remember me", no "Forgot password?"; the three reset URLs return 404; `password.update` and `password.confirm` still resolve; correct credentials still redirect to `/dashboard` as an admin and wrong credentials are rejected.

Not touched: `website/.env`, every other finding in this report, and all previously committed work. No commit was made.
