# Listing Reviews and Ratings

Star ratings plus optional written reviews on a listing, end to end: a Laravel
API, admin moderation, and the Flutter app.

Branch: `feature/listing-reviews`

Commits:

| Commit | Contents |
| --- | --- |
| `6aaae13` | Table, model, review API, rating summaries on listing payloads |
| `99f0b8f` | Admin moderation screen and the Laravel test suite |
| `6f40ca4` | Flutter reviews UI, card ratings, and Flutter tests |

## Rules

A review is one rating plus an optional comment from a signed-in buyer to a
listing they did not create.

| Rule | Value |
| --- | --- |
| Who may write | Sanctum-authenticated user with an `ACTIVE` account |
| Whose listing | Never your own, resolved `listing -> farmer -> buyer -> user` |
| Rating | Integer `1..5`, enforced by a `CHECK` constraint |
| Comment | Optional, trimmed, at most 300 characters |
| One per pair | Unique on `(LST_ID, USR_ID)`; submitting again updates the row |
| Editing | The same endpoint and the same sheet as writing; there is no second form |
| Deleting | The author's own row only |
| Removed listing | No reviews accepted |
| Visibility | `VISIBLE` or `HIDDEN`; only `VISIBLE` counts towards the average |

Blocked cases return the reason as a sentence the app shows verbatim, rather than
a generic failure: "This is your own listing.", "Sign in to write a review.",
"Your account must be active to review."

## Database

`database/migrations/2026_10_05_000001_create_listing_review_table.php`

```
LRV_ID         char(6)             primary key
LST_ID         char(6)             -> listing (LST_ID), cascade delete
USR_ID         char(6)             -> user (USR_ID), cascade delete
LRV_RATING     tinyint unsigned    CHECK (LRV_RATING BETWEEN 1 AND 5)
LRV_COMMENT    varchar(300)        nullable
LRV_STATUS     enum                VISIBLE | HIDDEN, default VISIBLE
LRV_CREATED_AT datetime(6)
LRV_UPDATED_AT datetime(6)
```

The migration is additive only. An earlier draft called
`Schema::dropIfExists()` first, which would have silently discarded existing
reviews on every deploy; that call is gone.

`database/schema/mysql-schema.sql` was deliberately **not** regenerated. It
carries 28 tables and 27 `INSERT` statements, and the live `capstone_db` holds
43 listings, 26 users and 10 farms, so regenerating it would have committed real
data into the repository. A fresh database was verified separately: Laravel loads
the dump first, then the review migration creates the table.

A backup of the pre-migration database is at
`backups/capstone_db-20261005-084151.sql`; `backups/` is git-ignored.

## API

Public read, authenticated write, on the same path.

| Method | Path | Auth | Returns |
| --- | --- | --- | --- |
| GET | `/api/listings/{listingId}/reviews` | optional | `reviews`, `summary`, `my_review`, `can_review`, `review_blocked_reason`, pagination |
| POST | `/api/listings/{listingId}/reviews` | required | `201` new / `200` updated, `review`, `summary` |
| DELETE | `/api/listings/{listingId}/reviews` | required | `summary` |

The read is public because browsing is: an unauthenticated caller gets the list
and the average, with `can_review: false`. The bearer token is attached when one
exists and is simply omitted otherwise.

`POST` returns `201` for a new review and `200` when it updated the caller's
existing row, so the client can word the confirmation correctly.

`DELETE` is scoped to the author. Asking for someone else's review returns
`404`, not `403` — a `403` would confirm that the row exists.

```json
{
  "reviews": [
    {
      "id": "LRV0001",
      "listing_id": "LST0001",
      "rating": 5,
      "comment": "Very fresh, big crates.",
      "reviewer": "Maria S.",
      "created_at": "2026-10-01T08:30:00.000000Z",
      "updated_at": "2026-10-01T08:30:00.000000Z",
      "is_mine": false
    }
  ],
  "summary": { "average": 4.3, "count": 7 },
  "my_review": null,
  "can_review": true,
  "review_blocked_reason": null,
  "current_page": 1,
  "last_page": 2,
  "per_page": 5,
  "total": 7
}
```

### Rating summaries on listings

`Listing::withRatingSummary()` adds `rating_average` and `rating_count` as two
correlated subqueries in the listing query itself, so a feed of 20 listings costs
one extra round trip rather than 20. Applied to the public feed, product detail,
farm-profile listings reached from a map pin, and the seller's own listings.

`rating_average` is `null` when nothing is rated, never `0`. A brand new listing
has not been judged badly, and a `0` would say it had.

### Reviewer names

`ListingReview::reviewerName()` returns the first name plus the last initial,
built from `USR_NAME` alone. No email address, mobile number or full name is
ever selected, so there is nothing to strip at the display layer. Admin search
covers full names internally, but the moderation table renders the short form.

## Admin

`GET /reviews` with `PATCH /reviews/{id}/visibility`, behind `auth` + `admin`.

Search across reviewer, crop, farm, comment and review ID; filters for status and
rating; pagination that keeps the current query string. Moderation is reversible
hide/unhide only — there is no admin create, edit or delete, so an admin cannot
manufacture a review that a buyer did not write.

No `audit_log` row is written. The model's own docblock records that nothing in
the application currently writes to that table, and reports record their actions
in `report_action`; inventing a write path here would have implied a guarantee
that does not exist elsewhere.

## Flutter

New files:

| File | Contents |
| --- | --- |
| `lib/models/listing_review.dart` | `RatingSummary`, `ListingReview`, `ListingReviewsPage`, `ReviewPageResult`, `ReviewDraft` |
| `lib/services/review_service.dart` | `ReviewsGateway` interface and HTTP implementation |
| `lib/widgets/rating_stars.dart` | Read-only star row and tappable input |
| `lib/widgets/review_sheet.dart` | Write/edit bottom sheet |
| `lib/widgets/listing_reviews_section.dart` | Self-contained product-detail block |

`ReviewsGateway` is an interface with the screen taking it as an optional
constructor argument, matching how `MessagesGateway` and `ReportsGateway` are
already handled, so the product detail screen is widget-testable without a
server.

Ratings were added to `Listing`, `CropListing` and `SearchResultItem`, and are
shown conditionally on home cards, search results and the seller's crop rows.
Nothing renders for an unrated listing.

The reviews block sits after the Call and Message buttons on the product detail
screen. It was placed above them first, which pushed both buttons off screen on
a phone — the rating a buyer arrived with is already on the card, so the primary
actions keep their position and reviews follow.

### Behaviour worth knowing

- Averages are read as `num`, because PHP's `json_encode` drops the `.0` from a
  whole number and sends `average: 5`.
- `hasRatings` requires a non-null average **and** a positive count, so a
  malformed payload renders nothing instead of a lone score.
- The write action appears only on a positive `can_review`. A blocked viewer gets
  the server's sentence; an unknown one, such as after a failed read, gets no
  button at all, because offering it would collect a rating the server then
  refuses.
- A submit or delete merges the returned row and summary into the list already on
  screen instead of refetching, so expanding a second page and then writing does
  not discard it.
- `is_mine` comes from the server, so a row cannot be styled as the caller's own
  by comparing ids on the client.
- The star row rounds down when filling and prints the exact average beside it.

## Tests

Laravel, MySQL (`php artisan test -c phpunit.mysql.xml`):

| Suite | Result |
| --- | --- |
| `ListingReviewTest` | 29 passed, 126 assertions |
| `ReviewModerationTest` | 15 passed, 57 assertions |
| Whole suite | 208 passed, 26 failed |

The 26 failures are pre-existing and unrelated. They were confirmed by running
the same suite on `a580489`, the commit before this work started, where they fail
identically. They fall into two groups:

- Auth, registration, password, profile and `ExampleTest`: Breeze scaffolding
  tests writing to a `user.name` column that this project's `user` table does not
  have, plus a root route that redirects.
- `ReportModerationTest` and `ReportSubmissionTest`: report-action notification
  assertions.

Flutter:

| Suite | Result |
| --- | --- |
| `listing_review_model_test.dart` | 38 passed |
| `listing_reviews_section_test.dart` | 26 passed |
| Whole suite | 419 passed, 13 failed |

The 13 Flutter failures are the pre-existing tests that need a live backend:
`contact_log_network_test.dart`, `edit_farm_flow_network_test.dart`,
`farm_profile_network_test.dart`, and others that require a running API.

`flutter analyze` reports no issues.

Note for anyone running the Laravel tests: `C:\xampp\mysql\bin` must be on
`PATH`, or the suite fails with `'mysql' is not recognized`.

### Three bugs the tests caught

Recorded because each was invisible until exercised:

1. `ReviewPageResult` did not carry `my_review` or `can_review`, so the section
   discarded the server's answer and the write button could never enable.
2. `ListingReviewsPage.copyWith` treats a null argument as "leave this alone",
   so `withoutReview` left the deleted review in place as the sheet's prefill.
   It now clears through an explicit flag.
3. An unreviewed listing parsed an empty `reviewer` as an empty byline rather
   than falling back.

A fourth was caught by the existing suite rather than a new one: placing the
reviews block above the Call/Message buttons broke
`product_detail_display_test.dart` by pushing them off screen.

## Unrelated

Not touched by this work: image search (10 km radius, hidden confidence
percentages, availability badges, tight large-image cards, `Scanning image...`,
`ml_service\farmspot_9class_best.pt` on port 8001) and the exposed Roboflow key
plus the Google Drive model URL, which are worth rotating separately.