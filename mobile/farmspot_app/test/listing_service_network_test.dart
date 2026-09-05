import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server. Verifies the farmer listing service round-trip:
// categories -> my-listings -> create (JSON + multipart photo) -> status patch.
void main() {
  // Tiny but valid 1x1 JPEG.
  const tinyJpegBase64 =
      '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AKwA//9k=';

  test('farmer listing service round-trip against real backend', () async {
    SharedPreferences.setMockInitialValues({});

    await AuthService.logout();
    final error = await AuthService.login(
      'libando@gmail.com',
      'password123',
    );
    expect(error, isNull);

    final categories = await ListingService.fetchCropCategories();
    expect(categories, isNotEmpty);

    final before = await ListingService.fetchMyListings();
    expect(before, isNotEmpty);
    expect(before.first.status, isNotEmpty);

    final created = await ListingService.createListing(
      farmId: 'QUAOMR',
      categoryId: categories.first.id,
      status: 'SOON_TO_HARVEST',
      cropIcon: 'testbean',
      harvestDate: DateTime(2026, 9, 15),
    );
    expect(created.id, isNotEmpty);
    expect(created.status, 'SOON_TO_HARVEST');
    expect(created.availability, 'ACTIVE');

    final photo = XFile.fromData(
      base64Decode(tinyJpegBase64),
      name: 'bean.jpg',
    );
    final withPhoto = await ListingService.createListing(
      farmId: 'QUAOMR',
      categoryId: categories.first.id,
      status: 'AVAILABLE_NOW',
      cropIcon: 'testphoto',
      photo: photo,
    );
    expect(withPhoto.id, isNotEmpty);
    expect(withPhoto.image, isNotEmpty);

    final updated = await ListingService.updateListingStatus(
      listingId: withPhoto.id,
      status: 'NOT_AVAILABLE',
    );
    expect(updated.status, 'NOT_AVAILABLE');

    try {
      await ListingService.createListing(
        farmId: 'QUAOMR',
        categoryId: categories.first.id,
        status: 'BANANA',
      );
      fail('expected createListing to throw for invalid status');
    } catch (e) {
      expect(e, isA<Exception>());
    }
  });
}