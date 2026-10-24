# Weekly Sourcing backend

Premium accounts can save a weekly crop list, find all matching public farms, open farm profiles, and use existing directions. There is no distance cutoff and no automatic expiry of the saved list.

## Database

Migration `2026_10_24_000005_create_weekly_sourcing_list.php` adds `weekly_sourcing_list`: `USR_ID` (primary key and cascading user foreign key), JSON `CROPS`, and `UPDATED_AT`. Applied to the local application database. Existing listings and statuses are unchanged.

## API

Authenticated active-account endpoints, each enforcing current premium entitlement:
- GET `/api/sourcing/list`: own saved crops and crop catalog.
- PUT `/api/sourcing/list`: replace own selection, including clearing it.
- POST `/api/sourcing/matches`: match own saved selection, optional latitude/longitude pair; location is not stored.

Only approved, active-pin farms with active seller accounts and ACTIVE listings marked AVAILABLE_NOW or SOON_TO_HARVEST match. Known crop aliases are canonicalized. Unknown crops from real available listings are also selectable. Previously saved custom crops remain valid after stock disappears.

Expired on-sale listings remain included under existing visibility rules and carry an availability-confirmation warning. Unavailable and removed listings do not qualify. Available-now and upcoming crops are returned separately and labeled on the cards. Freshness warnings apply to available-now listings. Distance is straight-line, nearest first; farms without coordinates follow those with distances. Without buyer GPS all farms remain included, sorted by name, with distance unavailable. Unmatched crops are returned explicitly.

## Validation

MySQL feature tests cover account isolation, premium enforcement, saved choices, aliases, missing crops, distant farms, visibility, freshness, location validation, and sold-out custom selections. Flutter tests cover authenticated payloads, persistence, failed saves, actual results, missing crops, and missing GPS. Automatic alerts and route optimization remain outside this feature.

## Searchable crop picker

The main screen displays selected crops only. Add crops opens a scrollable, lazily built checkbox picker with partial-name and server-provided alias search, a selection counter, and explicit confirmation. Closing the picker discards pending changes. Selection survives search changes; the picker enforces the existing 50-crop limit. Categories are deferred until reliable crop category data exists.
