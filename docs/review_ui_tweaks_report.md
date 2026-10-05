# Listing reviews: preview, filters and readable scores

Branch `feature/review-ui-tweaks`, on top of `f04b090` (the original review
feature). Two commits:

- `5a6d764` — optional `rating`, `with_comment` and `sort` on the review read,
  plus `summary.rating_breakdown`.
- `bb7e291` — the Flutter preview, full list, review card and rating changes.

## What the buyer gets

**Product page.** Three reviews, the best ones rather than the newest, and one
`See all N reviews` link when there are more. Call and Message stay above the
reviews block and need no scrolling.

**See all reviews.** A full screen that loads the next page as you scroll, with
a sort selector (Best, Newest, Highest, Lowest) and chips for All, 5★–1★ and
With comments. Star selection is single-select and combines with With comments.
Any change resets to page one.

**Review cards.** Reviewer on the left, five stars hard against the right edge,
date under the name. Long names ellipsize and the stars keep their width.

**Scores.** One amber star plus the average, and the count when it fits, on home
cards, search results and seller rows. Nothing at all for an unrated listing.
Home cards show distance over the photo's bottom-right corner and put the rating
on the line under the crop name.

## Backend

`GET /api/listings/{id}/reviews` gained three optional parameters:

| Parameter | Values | Default |
|---|---|---|
| `rating` | `1`–`5` | all |
| `with_comment` | `true` / `false` | all |
| `sort` | `newest`, `best`, `highest`, `lowest` | `newest` |

Absent or unusable values fall back to the previous behaviour rather than
erroring, so no existing request changes shape. `summary` gained
`rating_breakdown`, a count per star band.

`best` orders by rating descending, then reviews that left words, then newest,
with an ID tiebreak. `highest` and `lowest` order by rating with newest as the
tiebreak.

### Two things that had to be decided

**Summary ignores the filter.** The average, the count and `rating_breakdown`
are computed over every `VISIBLE` review, not the filtered set. Otherwise a
listing averaging 4.3 would advertise itself as 5.0 the moment a buyer tapped
the 5★ chip, and the counts printed beside the chips would change under the tap
that produced them.

**Filtering stays inside `visible()`.** A hidden review cannot be narrowed to by
guessing its rating.

`my_review` and `can_review` are deliberately filter-independent: a buyer who has
reviewed keeps the edit and delete actions under any active filter.

### A bug worth recording

The first cut of `ListingReviewController::sort()` validated with
`array_key_exists($sort, self::SORTS)`. `SORTS` is a list, so a key lookup
answered "no" for *every* input including `best`, and every request silently
served newest-first — a buyer asking for the best reviews got the newest. Two
tests caught it (`sort best prefers high rating then commented then newest`,
`sort lowest puts the worst rating first`). Fixed with `in_array(..., true)`.

## Decisions worth knowing about

- **Preview is 3, sorted best.** A preview shows the shape of what is there. On
  most listings the newest review is a bare star rating, which is the least
  informative of the three on offer.
- **The cap is enforced on the response too**, not only in `per_page=3`, so a
  server ignoring the parameter cannot push five cards and a write button below
  the fold on a phone.
- **Paging moved to the new screen.** A "Show more" button at the bottom of a
  product page is a button a buyer has to discover. The `Show more reviews`
  widget test was replaced with four preview tests, since that behaviour is what
  changed.
- **Your own review is pinned, not filtered.** A 5★ filter hides a buyer's own
  3★ review, and a review you cannot find is one you cannot edit or withdraw.
  When the active filter excludes it, the row is pinned above the list with a
  line saying so — otherwise a lone row at the top looks like a broken filter.
  It is never duplicated when the rows already contain it.
- **Tapping the active star chip clears it.** Single-select chips mean the
  active one has to be the way back to All; requiring a separate control to undo
  a tap means aiming at "All" instead.
- **A star band with no reviews prints without a count.** "5 stars (0)" invites a
  tap that cannot return anything.
- **`with_comment=false` is never sent.** It would mean "only bare star
  ratings", which is not what an untouched screen means.
- **Filters reach the server, so `RatingFilter`/`ReviewFilter` state lives in
  the screen, not the widget.** List, chip counts and header average are three
  views of one request.
- **Two paging behaviours were fixed while testing.** A failed page used to
  re-request itself on every scroll notification, because re-rendering the
  footer produces another one — a server that is down got hammered; only the
  button retries now. And a recovered page left its error and retry button
  sitting under the rows fetched after it.
- **Farm profile test finders were scoped, not loosened.** The farm name and
  distance now also appear on each listing card, so a whole-screen count answers
  a different question than "does the header show it". Added
  `FarmProfileScreen.headerKey` and `statsRowKey` and scoped the two affected
  assertions.

## Test data

No rows were added to `capstone_db`. One leftover review from the earlier
session (`LRV_ID = HAAOAE`) was found and deleted. Backend tests use
`RefreshDatabase` against `capstone_test` with transacting rows.

## Tests

| Command | Result |
|---|---|
| `php artisan test -c phpunit.mysql.xml --filter=ReviewFilterSortTest` | 39 passed, 121 assertions |
| `--filter="ListingReviewTest\|ReviewModerationTest\|ReviewFilterSortTest"` | 83 passed, 304 assertions |
| `php artisan test -c phpunit.mysql.xml` | 247 passed, **26 failed** — all pre-existing |
| `flutter analyze` | No issues |
| `flutter test` | 459 passed, **13 failed** — all pre-existing |

New Flutter coverage: 29 screen/widget tests in `all_reviews_screen_test.dart`
(reading, filters, sorting, paging, own review, compact label, card layout) and
9 added to the model and section suites — 45 and 30 respectively.

### The 26 Laravel failures are pre-existing

`Auth\*` (15), `ProfileTest` (5), `ExampleTest`, `ReportModerationTest` (2),
`ReportSubmissionTest` (2). Unrelated to reviews; the review suites are green.

### The 13 Flutter failures are pre-existing

`contact_log_network_test.dart` (2), `edit_farm_flow_network_test.dart`,
`farm_profile_network_test.dart` (3), `farm_stats_network_test.dart`,
`home_feed_mapping_test.dart`, `insights_network_test.dart`,
`listing_photos_gallery_network_test.dart`, `listing_service_network_test.dart`,
`seller_reactivation_network_test.dart` (2). All hit a live backend that is not
reachable from the test run — "Could not reach the server."

## Not done

- No admin, ML, farm-setup or unrelated screen touched.
- No route, table or widget removed; `RatingStars` is still used on the product
  detail header and inside review cards, where the drawn row is the point.
- `mobile/farmspot_app/test/listing_review_model_test.dart` — the new `const`
  breakdown/sort/filter tests use `final`, since the factories are not const.