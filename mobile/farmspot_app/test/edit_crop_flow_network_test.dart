import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/farm_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server. Mirrors the EditCropScreen (AddCropScreen edit mode)
// submit sequence:
//   1. createListing(...) with a photo — the listing a seller would later edit.
//   2. updateListing(...) — category/name/status/harvest-date PATCH round-trip.
//   3. updateListingPhoto(...) — photo replace gives a NEW cloud URL.
//   4. deleteListing(...) — the listing disappears from fetchMyListings and the
//      public fetchListing 404s. Self-cleaning, so no residue is left behind.
void main() {
  test('edit-crop data flow round-trip against real backend', () async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.logout();
    final error = await AuthService.login(
      'libando@gmail.com',
      'password123',
    );
    expect(error, isNull);

    // Same setup the AddCropScreen ("Which Farm?" + category grid) uses.
    final farms = await FarmService.getFarms();
    expect(farms, isNotEmpty);
    final farmId = farms.first['FRM_ID'] as String?;
    expect(farmId, isNotEmpty);

    final categories = await ListingService.fetchCropCategories();
    expect(categories, isNotEmpty);

    // 1x1 transparent PNG — enough for the backend's image validation.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    // ---- Create a listing WITH a photo (the thing we'll edit + delete) ----
    final created = await ListingService.createListing(
      farmId: farmId!,
      categoryId: categories.first.id,
      status: 'SOON_TO_HARVEST',
      cropIcon: 'Edit-Test Crop',
      harvestDate: DateTime(2026, 10, 1),
      photo: XFile.fromData(pngBytes, name: 'before.png'),
    );
    expect(created.id, isNotEmpty);
    expect(created.cropIcon, 'Edit-Test Crop');
    expect(created.status, 'SOON_TO_HARVEST');
    expect(created.image, isNotNull);
    expect(created.image, isNotEmpty);

    // ---- Full edit: category + name + status + harvest date (JSON PATCH) ----
    final edited = await ListingService.updateListing(
      listingId: created.id,
      categoryId: categories.first.id,
      cropIcon: 'Edit-Test Crop Renamed',
      harvestDate: '2026-11-01',
      status: 'AVAILABLE_NOW',
    );
    expect(edited.id, created.id);
    expect(edited.cropIcon, 'Edit-Test Crop Renamed');
    expect(edited.status, 'AVAILABLE_NOW');
    expect(edited.harvestDate, '2026-11-01');
    expect(edited.categoryId, categories.first.id);

    // ---- Photo-only edit: same listing, new image URL ----
    final photoEdited = await ListingService.updateListingPhoto(
      listingId: created.id,
      photo: XFile.fromData(pngBytes, name: 'after.png'),
    );
    expect(photoEdited.id, created.id);
    expect(photoEdited.image, isNotNull);
    expect(photoEdited.image, isNotEmpty);
    expect(photoEdited.image, isNot(equals(created.image)),
        reason: 'replacing the photo must produce a new Cloudinary URL');

    // Values edited earlier survive the photo-only call.
    expect(photoEdited.cropIcon, 'Edit-Test Crop Renamed');
    expect(photoEdited.status, 'AVAILABLE_NOW');

    // ---- Delete: gone from MyFarm list and 404 from the public endpoint ----
    await ListingService.deleteListing(created.id);

    final mine = await ListingService.fetchMyListings();
    expect(mine.where((l) => l.id == created.id), isEmpty);

    var publicGone = false;
    try {
      await ListingService.fetchListing(created.id);
    } catch (e) {
      publicGone = true;
    }
    expect(publicGone, isTrue);
  });
}