import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/farm_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server. Mirrors the MyFarmScreen data flows:
//   1. Farm card: FarmService.getFarms() -> first farm's FRM_NAME/FRM_BARANGAY/
//      FRM_STATUS (the "Live" badge reads FRM_STATUS == APPROVED).
//   2. Listings: ListingService.fetchMyListings() -> label via cropIcon??
//      categoryName, and status always one of the 3 backend enum values
//      (the tile's status chip + bottom sheet map from these exact strings).
//   3. Status edit: updateListingStatus() persists, shows up on re-fetch, and
//      the original status is restored.
void main() {
  test('my farm screen data flow round-trip against real backend', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
    final error = await AuthService.login(
      'libando@gmail.com',
      'password123',
    );
    expect(error, isNull);

    // ---- Farm info card ----
    final farms = await FarmService.getFarms();
    expect(farms, isNotEmpty);
    final first = farms.first;
    expect(first['FRM_ID'] as String?, isNotEmpty);
    expect(first['FRM_NAME'] as String?, isNotEmpty);
    expect(first['FRM_BARANGAY'] as String?, isNotEmpty);
    expect(first['FRM_STATUS'] as String?, 'APPROVED');

    // ---- Listings list ----
    final listings = await ListingService.fetchMyListings();
    expect(listings, isNotEmpty);
    const statusEnum = {'AVAILABLE_NOW', 'SOON_TO_HARVEST', 'NOT_AVAILABLE'};
    for (final l in listings) {
      expect(l.cropIcon ?? l.categoryName ?? 'Crop', isNotEmpty);
      expect(statusEnum, contains(l.status));
    }

    // ---- Status edit round-trip ----
    final target = listings.first;
    final flip = target.status == 'NOT_AVAILABLE'
        ? 'SOON_TO_HARVEST'
        : 'NOT_AVAILABLE';

    final updated = await ListingService.updateListingStatus(
      listingId: target.id,
      status: flip,
    );
    expect(updated.id, target.id);
    expect(updated.status, flip);

    // Re-fetch (what _loadListings does after an edit) shows the new status.
    final after = await ListingService.fetchMyListings();
    expect(after.firstWhere((l) => l.id == target.id).status, flip);

    // Restore the original status so the dev DB isn't left flipped.
    await ListingService.updateListingStatus(
      listingId: target.id,
      status: target.status,
    );
    final restored = await ListingService.fetchMyListings();
    expect(
      restored.firstWhere((l) => l.id == target.id).status,
      target.status,
    );
  });
}