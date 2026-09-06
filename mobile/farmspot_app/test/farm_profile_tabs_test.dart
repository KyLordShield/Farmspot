import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/screens/farm_profile_screen.dart';
import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

// Widget-level coverage for FarmProfileScreen using a preloaded profile
// (constructor's `initialData`), so the layout, stats row, sticky tabs,
// client-side filtering, empty state, and tap-through behave predictably with
// no network. Live JSON -> model parsing is covered separately by
// farm_profile_network_test against the real backend.

CropListing _crop(String name, String status) => CropListing(
      cropName: name,
      farmName: 'Mr. A Farm',
      cropType: 'Vegetables',
      status: status,
      farmId: 'FRMA',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: '0.4 km away',
      contactNumber: '09870000000',
    );

FarmProfileData _profile() => FarmProfileData(
      id: 'FRMA',
      name: 'Mr. A Farm',
      barangay: 'Sudlon II',
      status: 'APPROVED',
      // No "Not Available" listings on purpose: that tab exercises the empty
      // state. 2 available + 1 soon-to-harvest = 3 cards on "All".
      listings: [
        _crop('Cabbage', 'AVAILABLE_NOW'),
        _crop('Carrot', 'AVAILABLE_NOW'),
        _crop('Kangkong', 'SOON_TO_HARVEST'),
      ],
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: FarmProfileScreen(farmId: 'FRMA', initialData: _profile())),
  );
  await tester.pumpAndSettle();
}

Finder _tabTap(String label) => find.descendant(
      of: find.byType(TabBar),
      matching: find.text(label),
    );

void main() {
  testWidgets('header shows banner, farm name, location, and availability stats',
      (tester) async {
    await _pump(tester);

    expect(find.text('Mr. A Farm'), findsOneWidget);
    expect(find.text('Sudlon II'), findsOneWidget);

    // Stats row: AVAILABLE_NOW count + distance reused from the feed.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('0.4 km away'), findsOneWidget);
  });

  testWidgets('All tab shows every listing via the shared CropCardGrid',
      (tester) async {
    await _pump(tester);
    expect(find.byType(CropCard), findsNWidgets(3));
  });

  testWidgets('tabs filter the fetched list client-side', (tester) async {
    await _pump(tester);

    await tester.tap(_tabTap('Available Now'));
    await tester.pumpAndSettle();
    expect(find.byType(CropCard), findsNWidgets(2));

    await tester.tap(_tabTap('Soon to Harvest'));
    await tester.pumpAndSettle();
    expect(find.byType(CropCard), findsNWidgets(1));
    expect(find.text('Kangkong'), findsOneWidget);

    await tester.tap(_tabTap('All'));
    await tester.pumpAndSettle();
    expect(find.byType(CropCard), findsNWidgets(3));
  });

  testWidgets('empty tab shows centered empty message instead of a grid',
      (tester) async {
    await _pump(tester);

    await tester.tap(_tabTap('Not Available'));
    await tester.pumpAndSettle();

    expect(find.byType(CropCard), findsNothing);
    expect(find.text('No listings in this category right now'), findsOneWidget);
  });

  testWidgets('tapping a crop card opens the existing ProductDetailScreen',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Cabbage'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  testWidgets('farm name on the detail screen opens FarmProfileScreen',
      (tester) async {
    final listing = CropListing(
      cropName: 'Cabbage',
      farmName: 'Mr. A Farm',
      cropType: 'Vegetables',
      status: 'AVAILABLE_NOW',
      farmId: 'FRMA',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
    );
    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(listing: listing)),
    );
    await tester.pump();

    await tester.tap(find.text('Mr. A Farm'));
    // Let the push transition start (screen fetch is async/irrelevant here).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(FarmProfileScreen), findsOneWidget);
  });
}