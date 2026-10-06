# FarmSpot Admin — UI Polish Report

Branch: `feature/admin-ui-polish` (from `main` @ `98442f8`)
Scope compliance: all changes are confined to `website/resources/views`, `website/public/css`, and `website/public/js`. **No backend**, routes, models, controllers, requests, config, `.env`, database, or API code was touched. No form action, HTTP method, field/input name, `@csrf`, `@method`, `route()` call, query string, or pagination call was changed.

## Summary

The FarmSpot admin panel had a working, solid Bootstrap design system already. This pass tightened the shared language (design tokens, contrast, type scale, spacing, motion), made the navigation behave correctly on small screens, and upgraded every destructive/status action and flash message to a consistent SweetAlert2 treatment with a no-JS fallback. Zero backend logic changed.

## Files changed

```
website/public/css/style.css                       | design tokens, badge/table contrast, topbar + off-canvas sidebar, reduced-motion
website/public/js/global.js                        | NEW — sidebar drawer on mobile, active-nav highlighting by path
website/public/js/admin-alerts.js                  | NEW — toasts, confirms, dropdown confirm/revert, submit spinner, validation toast
website/resources/views/layouts/app.blade.php      | title pattern, topbar + overlay + sidebar id, SweetAlert2 + helper scripts, logout confirm
website/resources/views/auth/login.blade.php       | brand-title layout, focus-visible ring, submit guard
website/resources/views/dashboard.blade.php        | chart aria-labels, dead Export button hint
website/resources/views/analytics.blade.php        | chart aria-labels, dead Export button hint
website/resources/views/users.blade.php            | friendly status labels, deactivate confirm
website/resources/views/users/create.blade.php     | submit spinner
website/resources/views/users/edit.blade.php       | submit spinner
website/resources/views/users/show.blade.php       | friendly status labels
website/resources/views/listings.blade.php         | remove-listing confirm
website/resources/views/listings/edit.blade.php    | submit spinner
website/resources/views/listings/show.blade.php    | friendly Availability label
website/resources/views/partials/_category-panel.blade.php | category-delete confirm (data-confirm; panel script untouched)
website/resources/views/reports.blade.php          | status dropdown confirm + revert (auto-submit)
website/resources/views/reports/show.blade.php     | undo/action/status confirms, friendly subject labels, status form spinner
website/resources/views/reviews.blade.php          | star badge contrast, hide/show confirm
website/resources/views/seller-requests/show.blade.php | approve/reject confirms
website/resources/views/whitelist.blade.php        | deactivate confirm
website/resources/views/whitelist/create.blade.php | submit spinner
website/resources/views/whitelist/show.blade.php   | deactivate confirm
```

Full diff stat (below) confirms **22 files, +716 / −89**, all inside `resources/views` + `public`.

## Design tokens (added to `:root`)

- `--amber-text: #8a5f00` and `--slate-text: #465560` — dark text variants for badges (WCAG AA on the soft tints); `--amber`/`--slate` kept for icons.
- `--text-heading: #45534b` — table header color for readable uppercase headers.
- `--radius-sm: 7px`, `--radius-md: 10px` — shared radii.
- `--shadow-sm / --shadow-md / --shadow-lg` — consistent elevation for cards, panels, overlays.
- `--ease: 150ms cubic-bezier(.4,0,.2,1)` — one motion curve for all transitions.

Applied: badge text contrast, data-table + detail-table headers (`11px → 13px`, darker), table body `13.5 → 14px`, `accent-color`, button/icon/stat-card/panel transitions + hover shadows, `focus-visible` rings on icon buttons and the login button, and a `prefers-reduced-motion` media query.

## Toasts (SweetAlert2, top-right, ~3.4 s, progress bar)

Every page-level flash is promoted automatically by `admin-alerts.js`; the original Bootstrap alert stays in the DOM as the no-JS fallback and is hidden when JS runs:

| Page | Trigger | Toast |
|---|---|---|
| Users list | `session('success')` | success |
| Listings list | `session('success')` / `session('error')` | success / error |
| Reports list | `session('success')` | success |
| Reviews list | `session('success')` / `session('error')` | success / error |
| Whitelist list | `session('success')` | success |
| Whitelist create | `$errors` block | error (list) |
| Users/Seller-Requests show | `session('success')` / `session('error')` | success / error |
| Listings edit, Users create/edit | `$errors` block | error (list) |
| Any page with `.is-invalid` and no promoted error alert | client-side only | warning "fix the highlighted fields" |

## Confirm dialogs (`data-confirm-*`, generic helper)

All use SweetAlert2 with the correct tone (`danger` = red button) and fall back to native `confirm()` if SweetAlert2 is unavailable. Confirmed submission goes through `form.requestSubmit()` so HTML validation still applies.

| Action | Dialog |
|---|---|
| Log out (sidebar) | "Log out?" |
| Deactivate user (users list) | danger |
| Remove listing (listings list) | danger |
| Delete category (Category panel) | danger |
| Hide review (reviews list) | danger |
| Show review again (reviews list) | primary |
| Deactivate number (whitelist list + show) | danger |
| Approve seller request (seller-requests show) | primary |
| Reject seller request (seller-requests show) | danger |
| Undo most recent action (reports show) | primary |
| Take-action buttons (reports show) | danger |
| Update report status (reports show) | primary (submit guide, not confirm) |
| Report status dropdown (reports list) | confirm + revert on cancel |

## Submit-button spinner

Create/edit/save forms are guarded against double submission: `data-auto-spinner` disables the submit button and shows a Bootstrap spinner. Applied to users create/edit, whitelist create, listings edit, reports-show status form, and the login button (inline). Not applied to confirm flows or the logout form.

## Autonomy decisions & skips

1. **Profile page (`profile/*`, `/profile`) — SKIPPED.** Pre-existing broken Breeze scaffold, not reachable from the sidebar. Evidence: `profile/edit.blade.php` uses `<x-app-layout>` (component does not exist → 500 on load); `ProfileController::update` fills `name`/`email`/`password`, but the admin `User` model `$fillable` is `USR_NAME`/`USR_EMAIL`/`USR_PASSWORD` (`app/Models/User.php:39`) — the updates cannot persist without a backend change. Rebuilding the views would produce a good-looking form that errors on save. Reported per the "skip + list it" rule.
2. **`register.blade.php`, `welcome.blade.php`, `layouts/navigation.blade.php`, Breeze components** — dead/unrouted scaffolding (no register route in `routes/auth.php`; `/` redirects to login). Not part of the panel; left untouched.
3. **Category panel** — kept its own JS (it rewrites `form.action`/`_method` for create↔update). Only the delete form's native `confirm()` was swapped for `data-confirm`; the panel script is otherwise untouched.
4. **Export Data buttons (Dashboard, Analytics)** — do nothing today; a hint `title` was added, not a fake action. A real export needs a backend endpoint (out of scope).
5. **Analytics "Seasonal Trends" rows and "Searches today/Contacts made" zeros** — pre-existing hard-coded/zero content; left as-is (not inventing data, not hiding it).
6. **Font stack** — kept the offline-safe system font stack; no Google Fonts dependency added.
7. **Responsive sidebar** — implemented a custom topbar + off-canvas drawer <992px (no Bootstrap `offcanvas` dependency), replacing the previous stacked-nav behavior; original desktop sidebar layout unchanged.
8. **Active nav** — highlighted client-side in `global.js` by matching the browser path, so no server-side helper was needed.
9. **Filter selects** (search/type/status on list pages) — intentionally left as auto-submit without a confirm: changing a *filter* is not a state change. Only the per-row report *status* dropdown confirms.

## Quality checks

- `php artisan view:clear` + `php artisan view:cache` — all Blade templates compile.
- `php artisan route:list` — every route name used in the views resolves (verified `users.*`, `listings.*`, `categories.*`, `reports.*`, `reviews.*`, `whitelist.*`, `seller-requests.*`, `dashboard`, `analytics`, `logout`, `login`, `password.*`, etc.).
- `node --check` on `public/js/admin-alerts.js` and `public/js/global.js` — both valid.
- `git diff --stat main...HEAD` — only `website/public/` and `website/resources/views/` files changed.
- Grep of the removed diff lines for `@csrf`, `@method`, `name="` — none removed.
- Grep for leftover inline `onsubmit="return confirm(` — none (all converted to `data-confirm-*`).
- No tests run that touch `capstone_db`; nothing destructive executed. No migrations/seeders run.

## Manual test checklist

1. Load Dashboard → active sidebar item highlighted; on a ≤992px-wide window the topbar hamburger opens the drawer and the overlay closes it (Esc too).
2. Data tables → unambiguous column headers and readable body text; badges (active/amber/neutral) legible.
3. Users → deactivate shows a red confirm; confirm submit deactivates (success toast); format filter clears filters.
4. Listings → remove listing confirms; edit form shows spinner and disables the button on submit; category panel opens, create/edit icon picker still works, delete of an unused category confirms.
5. Reports → the row status dropdown asks to confirm and **reverts** when cancelled; reports show: undo, take-action, and update-status all confirm/correctly submit; subject status labels readable.
6. Reviews → hide/show confirms with correct tone; star rating badge legible.
7. Whitelist → deactivate confirms; create form spinner.
8. Seller Requests → approve/reject confirm.
9. Logout → confirm dialog then returns to sign-in.
10. Login → submit disables + spinner; brand header no longer overlaps "Sign In".
11. Hard-refresh page with a flash message → toast, not an inline alert; disable JS once → all original alerts/confirms still appear (fallbacks).
12. Reduce motion OS setting → no transitions animate.

## Open items (out of scope, no action taken)

- Profile page is broken at the backend layer (see skip #1).
- Export buttons need a real export endpoint.
- Analytics "Seasonal Trends" rows are hard-coded placeholders.