import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

// Widget-level check of the detail-screen name/image fix. Combined with
// home_feed_mapping_test (which proves live backend rows map into exactly this
// CropListing shape via toCropListing), this verifies the full path:
// real listing -> toggle -> detail renders name + photo; photo-less -> icon.
void main() {
  testWidgets('detail screen shows real crop name + photo, other fields intact',
      (tester) async {
    final listing = CropListing(
      cropName: 'Cabbage',
      farmName: 'Test Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: '0.4 km away',
      contactNumber: '09870000000',
      imageUrl: 'https://example.invalid/photo.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    // Real crop name as the headline (old static "Crop name:" label gone).
    expect(find.text('Cabbage'), findsOneWidget);
    expect(find.text('Crop name:'), findsNothing);

    // Already-working fields untouched.
    expect(find.text('Test Farm'), findsOneWidget);
    expect(find.text('Vegetables'), findsOneWidget);
    expect(find.textContaining('Call Seller'), findsOneWidget);
    expect(find.text('Send SMS to Seller'), findsOneWidget);
    expect(find.text('Sudlon II'), findsOneWidget);
    expect(find.text('Posted '), findsOneWidget);

    // Photo renders (Image.network; offline test env falls back gracefully).
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('photo-less listing shows placeholder icon instead of breaking',
      (tester) async {
    final listing = CropListing(
      cropName: 'Kangkong',
      farmName: 'Test Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: '0.4 km away',
      contactNumber: '09870000000',
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    expect(find.text('Kangkong'), findsOneWidget);
    expect(find.byIcon(Icons.eco), findsOneWidget); // placeholder icon
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Call Seller'), findsOneWidget);
    expect(find.text('Send SMS to Seller'), findsOneWidget);
  });
}