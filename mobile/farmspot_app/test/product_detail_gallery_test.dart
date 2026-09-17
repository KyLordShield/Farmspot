import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

// Offline widget checks for the swipeable photo gallery + description added to
// ProductDetailScreen: a multi-photo listing renders a PageView with a
// "n / N" counter and dot indicators that track swipes, plus the description;
// single-photo listings fall back to plain Image.network (no gallery, no
// counter) and photo-less listings keep the placeholder icon.
void main() {
  CropListing baseListing({List<String> photos = const []}) {
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
      imageUrl: photos.isNotEmpty ? photos.first : null,
      photoUrls: photos,
      description: null,
    );
  }

  testWidgets('multi-photo listing shows swipeable gallery with counter+dots+description',
      (tester) async {
    final listing = baseListing(photos: [
      'https://example.invalid/1.jpg',
      'https://example.invalid/2.jpg',
      'https://example.invalid/3.jpg',
    ]);
    // Descriptions are set on the mutable copy because CropListing is const-friendly.
    final withDesc = CropListing(
      cropName: listing.cropName,
      farmName: listing.farmName,
      cropType: listing.cropType,
      status: listing.status,
      barangay: listing.barangay,
      postedLabel: listing.postedLabel,
      expiresLabel: listing.expiresLabel,
      distance: listing.distance,
      contactNumber: listing.contactNumber,
      imageUrl: listing.imageUrl,
      photoUrls: listing.photoUrls,
      description: 'Fresh from the farm, quality checked.',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: withDesc)),
    );
    await tester.pump();

    // Gallery + counter start on photo 1 of 3; description is rendered.
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Fresh from the farm, quality checked.'), findsOneWidget);

    // Swiping right-to-left advances to photo 2 of 3.
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    // Swipe back to photo 1.
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    // Contact/status chrome unchanged.
    expect(find.textContaining('Call Seller'), findsOneWidget);
    expect(find.text('Send SMS to Seller'), findsOneWidget);
  });

  testWidgets('single-photo listing stays a plain image (no gallery, no counter) '
      'but still shows the description', (tester) async {
    final listing = baseListing(photos: ['https://example.invalid/1.jpg']);
    final withDesc = CropListing(
      cropName: listing.cropName,
      farmName: listing.farmName,
      cropType: listing.cropType,
      status: listing.status,
      barangay: listing.barangay,
      postedLabel: listing.postedLabel,
      expiresLabel: listing.expiresLabel,
      distance: listing.distance,
      contactNumber: listing.contactNumber,
      imageUrl: listing.imageUrl,
      photoUrls: listing.photoUrls,
      description: 'Small batch, farm-direct.',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: withDesc)),
    );
    await tester.pump();

    expect(find.byType(PageView), findsNothing);
    expect(find.textContaining('/ 1'), findsNothing);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Small batch, farm-direct.'), findsOneWidget);
  });

  testWidgets('photo-less listing keeps placeholder icon and no gallery/counter',
      (tester) async {
    final listing = baseListing(); // photos.isEmpty, description null

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    expect(find.byType(PageView), findsNothing);
    expect(find.textContaining('/ '), findsNothing);
    expect(find.byIcon(Icons.eco), findsOneWidget);
  });
}