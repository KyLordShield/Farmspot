# Farm and listing gallery limits

- A farm can have at most **4 photos total**, in setup and later uploads.
- A listing can have at most **5 photos total**, including retained existing
  photos and newly selected photos. Renewal replaces the old gallery with up to
  five fresh photos.
- The existing server limit of 5 MB per image still applies.

The app shows a photo count, stops offering an add button when full, and clips
picker results to the remaining slots. Farm edits count photos marked for
removal as free slots because those deletions are saved before new uploads.
Listing edits now offer removal of existing gallery photos for replacements.

Server array validation limits batch sizes. Append endpoints also lock the
parent farm/listing and check its current database photo count inside the
transaction before storing uploads. Repeated small uploads and overlapping
append requests cannot bypass the total cap. The legacy listing primary-photo
replacement endpoint checks its final count rather than counting a replacement
as an additional permanent photo.

Existing images are not removed automatically. Any older gallery already above
the cap must be reduced before more photos can be added. No data migration is
needed. The shared limits are `PhotoLimits` in the Flutter app and PHP API.

Tests cover full galleries, removal/replacement, oversized selections, farm
creation, repeated append requests, legacy primary replacement, and renewal.
