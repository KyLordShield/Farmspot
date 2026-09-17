import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/services/auth_service.dart';
import 'package:farmspot_app/services/listing_service.dart';

import 'photo_fixture.dart';

// Plain `test()` only (NO testWidgets) so real network is allowed against the
// local Laravel server. Covers the multi-photo listing lifecycle end to end:
// create with description + first photo -> batch-upload two more -> promote a
// photo to primary (image follows) -> delete the primary (auto-promote) ->
// delete the rest (image clears) -> description round-tripping -> cleanup.
void main() {
  XFile jpeg(String name) =>
      XFile.fromData(base64Decode(tinyJpegBase64), name: name);

  test(
    'listing photo gallery lifecycle against real backend',
    () async {
      SharedPreferences.setMockInitialValues({});

    await AuthService.logout();
    final error = await AuthService.login(
      'libando@gmail.com',
      'password123',
    );
    expect(error, isNull);

    final categories = await ListingService.fetchCropCategories();
    expect(categories, isNotEmpty);

    // Create with description + first (primary) photo.
    final created = await ListingService.createListing(
      farmId: 'FMWHEF',
      categoryId: categories.first.id,
      status: 'AVAILABLE_NOW',
      cropIcon: 'photogallerytest',
      description: 'Fresh from the farm, quality checked.',
      photo: jpeg('p1.jpg'),
    );
    final listingId = created.id;
    expect(listingId, isNotEmpty);
    expect(created.description, 'Fresh from the farm, quality checked.');
    expect(created.photos.length, 1);
    expect(created.photos.first.isPrimary, isTrue);
    expect(created.image, created.photos.first.url);

    try {
      // Batch-upload two more photos: all three present, first still primary.
      final updated = await ListingService.uploadListingPhotos(
        listingId: listingId,
        photos: [jpeg('p2.jpg'), jpeg('p3.jpg')],
      );
      expect(updated.photos.length, 3);
      expect(updated.photos.where((p) => p.isPrimary).length, 1);
      expect(updated.image, updated.photos.firstWhere((p) => p.isPrimary).url);

      // Promote a (non-primary) photo: exactly one primary, image re-points.
      final toPromote =
          updated.photos.firstWhere((p) => !p.isPrimary, orElse: () => updated.photos.first);
      final promoted = await ListingService.setPrimaryPhoto(
        listingId: listingId,
        photoId: toPromote.id,
      );
      expect(promoted.photos.length, 3);
      final primaryNow = promoted.photos.firstWhere((p) => p.isPrimary);
      expect(primaryNow.id, toPromote.id);
      expect(promoted.image, primaryNow.url);

      // Delete the primary: auto-promotes another photo and image follows.
      final afterDelete = await ListingService.deleteListingPhoto(
        listingId: listingId,
        photoId: toPromote.id,
      );
      expect(afterDelete.photos.length, 2);
      expect(afterDelete.photos.where((p) => p.isPrimary).length, 1);
      final newPrimary = afterDelete.photos.firstWhere((p) => p.isPrimary);
      expect(newPrimary.id, isNot(toPromote.id));
      expect(afterDelete.image, newPrimary.url);

      // Delete the rest: gallery empties and the thumbnail cache clears.
      for (final photo in afterDelete.photos.toList()) {
        final result = await ListingService.deleteListingPhoto(
          listingId: listingId,
          photoId: photo.id,
        );
        expect(result.photos.length, lessThan(afterDelete.photos.length));
      }
      final emptied = await ListingService.fetchListing(listingId);
      expect(emptied.photos, isEmpty);
      expect(emptied.image == null || emptied.image!.isEmpty, isTrue);

      // Description round-trip through updateListing.
      final edited = await ListingService.updateListing(
        listingId: listingId,
        description: 'Updated pick-up times.',
      );
      expect(edited.description, 'Updated pick-up times.');
      final cleared = await ListingService.updateListing(
        listingId: listingId,
        description: '',
      );
      expect(cleared.description == null || cleared.description!.isEmpty, isTrue);
    } finally {
      await ListingService.deleteListing(listingId);
    }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}