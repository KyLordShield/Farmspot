import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/models/listing_review.dart';
import 'package:farmspot_app/screens/farm_profile_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

// Offline widget checks for the whole-farm rating on the buyer-facing farm
// profile: the stats row shows "★ 4.4 (4 reviews)" when the farm has been
// rated, and shows nothing at all for an unreviewed farm (a "0.0" claim on a
// brand-new farm is a review nobody wrote).

CropListing _crop(String status) => CropListing(
      cropName: 'Cabbage',
      farmName: 'Mr. A Farm',
      cropType: 'Vegetables',
      status: status,
      farmId: 'FRMA',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: '0.4 km away',
    );

FarmProfileData _profile({RatingSummary? rating}) => FarmProfileData(
      id: 'FRMA',
      name: 'Mr. A Farm',
      barangay: 'Sudlon II',
      status: 'APPROVED',
      ratingSummary: rating ?? const RatingSummary.none(),
      listings: [
        _crop('AVAILABLE_NOW'),
        _crop('SOON_TO_HARVEST'),
      ],
    );

Future<void> _pump(
  WidgetTester tester,
  FarmProfileData profile, {
  double width = 800,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: FarmProfileScreen(farmId: 'FRMA', initialData: profile),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rated farm shows the aggregate rating in the stats row',
      (tester) async {
    await _pump(
      tester,
      _profile(rating: const RatingSummary(average: 4.4, count: 4)),
    );

    // Scoped to the stats row: the same "4.4" never appears on the listing
    // cards here, but the label guards against a whole-screen count drift.
    final stats = find.byKey(FarmProfileScreen.statsRowKey);
    expect(
      find.descendant(of: stats, matching: find.text('4.4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stats, matching: find.text('4 reviews')),
      findsOneWidget,
    );
  });

  testWidgets('unreviewed farm shows no rating stat at all', (tester) async {
    await _pump(tester, _profile());

    final stats = find.byKey(FarmProfileScreen.statsRowKey);
    expect(
      find.descendant(of: stats, matching: find.text('4.4')),
      findsNothing,
    );
    expect(
      find.descendant(of: stats, matching: find.text('reviews')),
      findsNothing,
    );
  });

  testWidgets('rating plus distance fits the 360px stats row without overflow',
      (tester) async {
    await _pump(
      tester,
      _profile(rating: const RatingSummary(average: 4.0, count: 12)),
      width: 360,
    );

    expect(tester.takeException(), isNull,
        reason: 'three stats must share the row width, never overflow');
  });
}