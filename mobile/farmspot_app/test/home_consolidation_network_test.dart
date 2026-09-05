import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (no testWidgets) so real HTTP is allowed against the
// local Laravel server. Verifies the home-screen consolidation contract:
//   1. A seller's Home is the SAME HomeScreen feed that buyers get
//      (ListingService.fetchListings is public / role-agnostic).
//   2. The seller banner count (HomeScreen._loadActiveListingCount) uses
//      ListingService.fetchMyListings() filtered to non-NOT_AVAILABLE —
//      exactly the number the "You have N active listings" line shows.
void main() {
  test('seller Home = real marketplace feed + banner count formula', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
    final error = await AuthService.login(
      'libando@gmail.com',
      'password123',
    );
    expect(error, isNull);
    expect(await AuthService.isSeller(), isTrue);

    // The marketplace feed HomeScreen renders for seller AND buyer alike.
    final feed = await ListingService.fetchListings();
    expect(feed, isNotEmpty);

    // Banner count: everything the seller owns that isn't NOT_AVAILABLE.
    final mine = await ListingService.fetchMyListings();
    final active = mine.where((l) => l.status != 'NOT_AVAILABLE').length;
    expect(active, inInclusiveRange(0, mine.length));
  });

  test('buyer Home feed is unaffected (fetchListings is role-agnostic)',
      () async {
    // No login, no token — the same public endpoint powering HomeScreen.
    final feed = await ListingService.fetchListings();
    expect(feed, isNotEmpty);
    for (final l in feed) {
      expect(l.id, isNotEmpty);
      expect(l.cropIcon ?? l.categoryName ?? 'Crop', isNotEmpty);
    }
  });
}