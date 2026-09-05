import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/farm_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server. Mirrors AddCropScreen._submit's exact service sequence:
// FarmService.getFarms() -> pick FRM_ID -> fetchCropCategories() ->
// createListing(crop label + harvest date) and confirms the created listing
// belongs to the farmer (fetchMyListings).
void main() {
  test('add-crop screen data flow round-trip against real backend', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
    final error = await AuthService.login(
      'libando@gmail.com',
      'password123',
    );
    expect(error, isNull);

    // Same call the "Which Farm?" picker makes in initState.
    final farms = await FarmService.getFarms();
    expect(farms, isNotEmpty);
    final first = farms.first;
    final farmId = first['FRM_ID'] as String?;
    expect(farmId, isNotEmpty);
    // The two fields the picker tile renders from the same map.
    expect(first.keys, contains('FRM_NAME'));
    expect(first.keys, contains('FRM_BARANGAY'));

    // Same call the "CROP CATEGORY" grid makes in initState.
    final categories = await ListingService.fetchCropCategories();
    expect(categories, isNotEmpty);

    // Same call the submit button makes (status + free-text label + date).
    final created = await ListingService.createListing(
      farmId: farmId!,
      categoryId: categories.first.id,
      status: 'SOON_TO_HARVEST',
      cropIcon: 'Screen-Test Crop',
      harvestDate: DateTime(2026, 10, 1),
    );
    expect(created.id, isNotEmpty);
    expect(created.status, 'SOON_TO_HARVEST');
    expect(created.availability, 'ACTIVE');
    expect(created.cropIcon, 'Screen-Test Crop');
    expect(created.harvestDate, isNotNull);

    // The listing must show up as the farmer's own listing afterwards.
    final mine = await ListingService.fetchMyListings();
    expect(mine.where((l) => l.id == created.id), isNotEmpty);
  });
}