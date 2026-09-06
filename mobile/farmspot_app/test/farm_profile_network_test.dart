import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/services/farm_service.dart';

// Plain `test()` only (no testWidgets) so real HTTP is allowed against the
// local Laravel server — same convention as the other *_network_test files.
// Verifies the Farm Profile backend contract the new FarmProfileScreen relies
// on: full farm + ALL listings (any status) ordered by status priority, flat
// listings mapping into CropListing with live farm identity, client-side
// filtering, and the fire-and-forget visit log.
const _fixtureFarmId = 'QUAOMR'; // libando's approved 31-listing farm

void main() {
  test('fetchFarmProfile returns farm details, photos, and all listings', () async {
    final profile = await FarmService.fetchFarmProfile(_fixtureFarmId);

    expect(profile.id, _fixtureFarmId);
    expect(profile.name, isNotEmpty);
    expect(profile.barangay, isNotEmpty);

    // Farm has uploaded photos -> the banner gets a real cover image.
    expect(profile.photos, isNotEmpty,
        reason: 'fixture farm should carry at least one photo');
    expect(profile.firstPhoto, profile.photos.first);

    // Farm Profile exposes EVERY listing (any status), unlike the buyer feed.
    expect(profile.listings.length, greaterThan(0));
  });

  test('listings are ordered AVAILABLE_NOW -> SOON_TO_HARVEST -> NOT_AVAILABLE',
      () async {
    final profile = await FarmService.fetchFarmProfile(_fixtureFarmId);
    int rank(String s) {
      switch (s) {
        case 'AVAILABLE_NOW':
          return 0;
        case 'SOON_TO_HARVEST':
          return 1;
        default:
          return 2;
      }
    }

    int? lastRank;
    for (final l in profile.listings) {
      final r = rank(l.status);
      if (lastRank != null) {
        expect(r, greaterThanOrEqualTo(lastRank),
            reason: '${l.cropName} broke the status-priority order');
      }
      lastRank = r;
    }

    // The live fixture has all three groups populated.
    expect(profile.filtered('AVAILABLE_NOW'), isNotEmpty);
    expect(profile.filtered('SOON_TO_HARVEST'), isNotEmpty);
    expect(profile.filtered('NOT_AVAILABLE'), isNotEmpty);
  });

  test('flat profile listings map into CropListing with live farm identity',
      () async {
    final profile = await FarmService.fetchFarmProfile(_fixtureFarmId);

    for (final l in profile.listings) {
      expect(l.status, isNotEmpty);
      expect(l.cropName, isNotEmpty);
      // Every profile listing must carry the farm id so ProductDetailScreen
      // can tap into this same farm profile.
      expect(l.farmId, _fixtureFarmId,
          reason: 'listing ${l.cropName} lost its farm identity');
    }

    expect(profile.availableNowCount, profile.filtered('AVAILABLE_NOW').length);
    expect(profile.filtered(null).length, profile.listings.length);
    // Distance stat reuses the feed's "X km away" string from the listings.
    expect(profile.distanceLabel, isNotNull);
    expect(profile.distanceLabel, isNotEmpty);
  });

  test('fetchFarmProfile throws a friendly error for an unknown farm', () async {
    expect(
      () => FarmService.fetchFarmProfile('BOGUS0'),
      throwsA(
        isA<Exception>().having((e) => e.toString(), 'message', contains('not found')),
      ),
    );
  });

  test('logFarmVisit is fire-and-forget and never throws', () async {
    // Happy path (real farm) and unknown farm alike must be silent.
    await FarmService.logFarmVisit(_fixtureFarmId);
    await FarmService.logFarmVisit('BOGUS0');
  });
}