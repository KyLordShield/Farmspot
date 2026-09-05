import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/services/listing_service.dart';

// Plain `test()` only (no testWidgets) so real HTTP is allowed against the
// local Laravel server. Verifies the Home-feed mapping fix:
//   - CropListing.cropName must carry the real crop name from crop_icon
//     (falling back to the category label for legacy rows with empty names),
//     not the category name as before.
//   - CropListing.imageUrl must carry the listing photo (LST_IMAGE /
//     Cloudinary URL) so CropCard can render it.
// Applies to EVERY listing on the feed — old backend-only rows and new
// AddCropScreen submissions alike (mapping bug, not a data-source problem).
void main() {
  test('listing -> CropListing mapping preserves crop name and photo',
      () async {
    final listings = await ListingService.fetchListings();
    expect(listings, isNotEmpty);

    // At least one listing carries a real photo (Cloudinary) — the photo a
    // fresh AddCropScreen submission uploaded.
    expect(listings.any((l) => (l.image ?? '').isNotEmpty), isTrue,
        reason: 'feed should include at least one photo-backed listing');

    var sawPhotoMapped = false;
    var sawNamedCrop = false;
    for (final l in listings) {
      final card = l.toCropListing();

      // cropName: prefers crop_icon, falls back to category name, never empty.
      expect(card.cropName, isNotEmpty);
      final expectedName =
          (l.cropIcon?.trim().isNotEmpty ?? false) ? l.cropIcon! : l.categoryName;
      expect(card.cropName, expectedName,
          reason: 'cropName must reflect crop_icon for listing ${l.id}');
      if ((l.cropIcon?.trim().isNotEmpty ?? false)) sawNamedCrop = true;

      // imageUrl mirrors the backend image field (null when listing has none).
      expect(card.imageUrl, l.image,
          reason: 'imageUrl must mirror image for listing ${l.id}');
      if ((l.image?.isNotEmpty ?? false)) sawPhotoMapped = true;

      // Category filtering semantics unchanged: cropType stays the category.
      expect(card.cropType, l.categoryName ?? 'Vegetable');
      expect(card.farmName, isNotEmpty);
    }

    // The real "Screen-Test Crop" + debugphoto / cabbage photo rows existed in
    // the feed; assert the fix demonstrably affects more than just one case.
    expect(sawNamedCrop, isTrue, reason: 'feed must include named crops');
    expect(sawPhotoMapped, isTrue,
        reason: 'at least one photo must reach the card layer');
  });
}