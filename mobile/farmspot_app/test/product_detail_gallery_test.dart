import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

// Offline widget checks for the redesigned product-detail screen: a single
// cover/header photo up top, a swipeable thumbnail strip ("Photos" section)
// below the header when >1 photos, and a full-screen viewer that opens on
// any tap.  Description text continues to display when non-empty, single-photo
// listings skip the strip entirely, and photo-less listings fall back to the
// placeholder icon.
void main() {
  CropListing makeListing({
    List<String> photos = const [],
    String? description,
  }) {
    final single = photos.isNotEmpty ? photos.first : null;
    return CropListing(
      cropName: 'Cabbage',
      farmName: 'Test Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: '0.4 km away',
      contactNumber: '09870000000',
      imageUrl: single,
      photoUrls: photos,
      description: description,
    );
  }

  // -----------------------------------------------------------
  // Multi-photo listing with description
  // -----------------------------------------------------------
  testWidgets(
      'multi-photo listing: header + strip + tap-to-view full-screen',
      (tester) async {
    final listing = makeListing(
      photos: [
        'https://example.invalid/1.jpg',
        'https://example.invalid/2.jpg',
        'https://example.invalid/3.jpg',
      ],
      description: 'Fresh from the farm, quality checked.',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    // No in-place gallery (old _PhotoGallery PageView) on the initial screen.
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(FullScreenPhotoViewer), findsNothing);

    // Hero/header shows a single cover photo.
    expect(find.byKey(const Key('detail_hero_photo')), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    // "Photos" strip with three thumbnails + description rendered.
    expect(find.byKey(const Key('detail_photo_strip')), findsOneWidget);
    expect(find.text('3 photos • tap to view'), findsOneWidget);
    expect(find.text('Fresh from the farm, quality checked.'), findsOneWidget);

    // Tapping the hero opens the full-screen viewer at photo 1.
    await tester.tap(find.byKey(const Key('detail_hero_photo')));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPhotoViewer), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    // Swipe left to photo 2.
    await tester.fling(
      find.byType(PageView),
      const Offset(-400, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    // Close the viewer.
    await tester.tap(find.byKey(const Key('viewer_close')));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPhotoViewer), findsNothing);

    // Tapping thumbnail 2 opens the viewer at photo 3.
    await tester.tap(find.byKey(const Key('detail_photo_thumb_2')));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPhotoViewer), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);

    // Verify swipe right (backward) from 3 → 2 of 3.
    await tester.fling(
      find.byType(PageView),
      const Offset(400, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('viewer_close')));
    await tester.pumpAndSettle();
  });

  // -----------------------------------------------------------
  // Single-photo listing with description
  // -----------------------------------------------------------
  testWidgets(
      'single-photo listing: header only, no strip, description visible',
      (tester) async {
    final listing = makeListing(
      photos: ['https://example.invalid/1.jpg'],
      description: 'Small batch, farm-direct.',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    expect(find.byType(PageView), findsNothing);
    expect(find.byType(FullScreenPhotoViewer), findsNothing);

    // Hero present, photo strip absent.
    expect(find.byKey(const Key('detail_hero_photo')), findsOneWidget);
    expect(find.byKey(const Key('detail_photo_strip')), findsNothing);

    expect(find.text('Small batch, farm-direct.'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  // -----------------------------------------------------------
  // Photo-less listing
  // -----------------------------------------------------------
  testWidgets(
      'photo-less listing: placeholder icon, no strip, no viewer',
      (tester) async {
    final listing = makeListing(); // empty photoUrls, no imageUrl

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    expect(find.byIcon(Icons.eco), findsOneWidget);
    expect(find.byKey(const Key('detail_photo_strip')), findsNothing);
    expect(find.byType(FullScreenPhotoViewer), findsNothing);
    expect(find.textContaining('Call Seller'), findsOneWidget);
  });
}
