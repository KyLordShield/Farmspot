# Seller My Farm

The farmer's own listing screen: every crop they have posted, paged, filterable
by state, and honest about moderation and complaints.

Branch: `feature/myfarm-ratings-status-paging`

Commits:

| Commit | Contents |
| --- | --- |
| `82368e7` | Laravel: paging, status filter, farm scoping, removed listings, report flag, farm summary |

## Why

`GET /api/my-listings` returned every listing a farmer has in one array. That is
fine for five rows and not for forty, and the row carried nothing about state:
a farmer whose crop had been taken down by an admin, or had a complaint open
against it, had no way to find that out from the app.

Two constraints shaped everything:

* **The response must stay backward compatible.** Existing callers send none of
  the new parameters and must get the old response, unchanged. Defaulting to
  paging would silently truncate them, so paging is opt-in.
* **The app may not learn anything it should not.** Reports are visible to the
  Association. A seller is told a report exists and nothing else.

## API

`GET /api/my-listings`, farmer-authenticated. Four optional parameters, all
additive:

| Parameter | Values | Default |
| --- | --- | --- |
| `page` | 1..last | 1 |
| `per_page` | 1..30, clamped not rejected | 10 |
| `farm_id` | one farm | every farm the farmer owns |
| `status` | `all` \| `active` \| `expired` \| `hidden` \| `under_review` | `all` |
| `include_removed` | `1` for the owner's view of a moderated listing | `0` |

The app always sends `page` and `per_page`, and sends `include_removed=1`
because a farmer is entitled to see the crop an admin took down.

### What each bucket means

| Bucket | Contents |
| --- | --- |
| `active` | on sale now, not expired, not removed, no open report |
| `expired` | `LST_EXPIRY_DATE` in the past |
| `hidden` | `LST_AVAILABILITY` is `REMOVED`, or an admin set `NOT_AVAILABLE` |
| `under_review` | a report is open against it |

`NOT_AVAILABLE` is also a value a farmer can pick for `LST_STATUS`, which is a
different column. A farmer saying "this crop is gone" is not the same as us
taking it off sale, so only `LST_AVAILABILITY` puts a listing in `hidden`.

### Paged response

```json
{
  "listings": [ /* ... */ ],
  "pagination": {
    "current_page": 2,
    "last_page": 5,
    "per_page": 10,
    "total": 47
  },
  "summary": {
    "total_listings": 47,
    "active_count": 30,
    "expired_count": 9,
    "hidden_count": 5,
    "under_review_count": 3,
    "review_count": 88,
    "rating_average": 4.1
  }
}
```

An **unpaged** response is still `{ "listings": [...] }`. That is the whole
reason `MyFarmListingPage.fromJson` treats a missing `pagination` block as one
complete page rather than as "there is more, forever".

### Summary scope

The summary describes the **selected farm scope, before the status filter**.
Tapping Expired narrows the list, not the totals: the chips have to keep showing
what the other buckets hold, or narrowing the list would look like the farm lost
listings. Counts partition the scope — each listing is in exactly one bucket —
and the four of them add up to `total_listings`.

`rating_average` is the **weighted** average over review rows, not the mean of
the per-listing averages, so a crop with 200 reviews cannot count the same as one
with 2. It is `null` when nothing has been reviewed, never `0` — an unreviewed
farm is not a zero-star one.

### Report privacy

The only report fact on the wire is `has_open_report: true|false`. No reporter
ID, no reason, no details, no report records. A seller who could read the
accusation, or who filed it, would know who to be angry at.

## Flutter

New files:

| File | Contents |
| --- | --- |
| `lib/models/my_farm_listing_page.dart` | `MyFarmStatusFilter`, `MyFarmSummary`, `MyFarmListingPage`, `ListingOwnerState` |
| `lib/services/my_farm_listings_service.dart` | `MyFarmListingsGateway` interface and HTTP implementation |
| `lib/widgets/my_farm_widgets.dart` | `MyFarmStatusChip`, `ListingOwnerChips`, `OwnerRatingLabel`, `ListingThumbnail`, `MyFarmListingRow`, `MyFarmFilterRow`, `MyFarmSummaryCard` |

Changed:

| File | Change |
| --- | --- |
| `lib/models/listing.dart` | additive `hasOpenReport`, default `false` so buyer payloads are unchanged |
| `lib/screens/seller/my_farm_screen.dart` | rewritten around `CustomScrollView` |
| `test/my_farm_switcher_test.dart` | updated for server-side farm scoping and sliver scrolling |

`MyFarmListingsGateway` is injected as an optional constructor argument, matching
`MessagesGateway` and `ReportsGateway`, so the screen is widget-testable without
a server.

### The screen

`ListView` → `CustomScrollView` with a `SliverList`, because ten rows of header
chrome plus an unbounded list is what the old screen was doing, and it rebuilt
every header on every append.

* **Server paging, not client slicing.** 400px from the bottom triggers the next
  page. Merging is by `LST_ID`, so a row that arrives on two pages — which is
  what happens when a listing is inserted between two requests — appears once.
* **A request generation counter.** Every reset bumps it, and a response whose
  generation is stale is dropped. Without it a slow page-1 reply could land on
  top of a filter change that had already replaced the list.
* **Farms first, then listings.** Listings are requested with a `farm_id`, so the
  selection must resolve before the first request. In parallel would mean
  fetching every farm's listings and throwing most away.
* **Failures do not empty the list.** A failed first load is a full-screen error
  with Retry; a failed later page keeps the rows and puts Retry underneath them.
* **Summary is the server's.** Counting loaded rows would make the card
  disagree with the thing it summarises — page 2 of 47 listings showing "10".

### Behaviour worth knowing

- `ListingOwnerChips.statusInfo` maps each `LST_STATUS` to its own label and
  colour, so the four states cannot become three visual languages.
- An unreviewed listing says "No reviews yet" on the farmer's row. Buyers get
  silence instead, because that line on every card of a new marketplace is noise
  — but a farmer asking how their crops are doing needs to tell no reviews from
  a hidden zero.
- The expiry countdown compares calendar days, not a `Duration`: "Expires in 2
  days" has to stay true at 11pm the day before, and a 47-hour remainder rounds
  to 1 day, not 2.
- The rating label only wraps in a `GestureDetector` when it has somewhere to go.
  A null handler still absorbs taps, which would swallow the row's own tap.
- `ListingThumbnail` requests `w_300, q_auto, f_auto` from Cloudinary and sets
  `cacheWidth`. A 68px box decoded from a 4000px photo is the largest single
  source of memory churn in a scrolling image list. A non-Cloudinary URL is
  passed through untouched — rewriting an arbitrary host's URL would break it.

## Tests

Laravel, MySQL:

| Suite | Result |
| --- | --- |
| `MyFarmListingPageTest` | 19 passed, 84 assertions |

```
$env:PATH = "C:\xampp\mysql\bin;" + $env:PATH
php artisan test -c phpunit.mysql.xml --filter MyFarmListingPageTest
```

Flutter:

| Suite | Result |
| --- | --- |
| `my_farm_listing_page_test.dart` | 26 passed |
| `my_farm_switcher_test.dart` | 15 passed |
| `flutter analyze lib test` | no issues |

### Three bugs the tests caught

1. **The first load asked for page 1 twice.** While page 1 was in flight the list
   was empty, so its scroll extent was near zero and "am I at the bottom?" was
   trivially true — the scroll listener fired and requested page 1 again. The
   second response then merged on top of the first, before the screen had a row
   to show. Guarded on `_initialLoading`.
2. **Retry under a loaded page did nothing.** The `_pageError != null` guard that
   stops a scroll event re-requesting a failed page also stopped the button that
   is meant to retry it. The stored error is now cleared first.
3. **Page-one rows appeared to vanish after scrolling.** Not a bug: the
   `SliverList` had unbuilt them. Worth recording because the first version of
   the test asserted on a row that was simply off-screen and read as a
   regression.

Three more were in the tests rather than the app, and are recorded because they
are the traps in testing a lazy sliver list: `scrollUntilVisible` only ever
scrolls **down**, so it cannot find a row that has scrolled off above the
viewport; a filter chip's label collides with a listing status chip of the same
word; and the trailing error sits under the bottom nav bar, so it must be
scrolled into the clear before it can be tapped.

## Unrelated

Not touched: image search, and the exposed Roboflow key plus the Google Drive
model URL, which are worth rotating separately.