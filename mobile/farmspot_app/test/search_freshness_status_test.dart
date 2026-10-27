import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/models/search_crop_group.dart';
import 'package:farmspot_app/screens/search_results_screen.dart';

void main() {
  for (final imageSearch in [false, true]) {
    testWidgets(
      '${imageSearch ? "image" : "text"} search checks freshness without changing valid statuses',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final past = DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String();
        final future = DateTime.now()
            .add(const Duration(days: 2))
            .toIso8601String();
        final listings = [
          Listing(
            id: 'OLD001',
            cropIcon: 'Cabbage',
            farmName: 'Old Farm',
            status: 'AVAILABLE_NOW',
            expiryDate: past,
          ),
          Listing(
            id: 'NEW001',
            cropIcon: 'Cabbage',
            farmName: 'Fresh Farm',
            status: 'AVAILABLE_NOW',
            expiryDate: future,
          ),
          Listing(
            id: 'SOON01',
            cropIcon: 'Cabbage',
            farmName: 'Harvest Farm',
            status: 'SOON_TO_HARVEST',
            expiryDate: past,
          ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: SearchResultsScreen(
              query: 'Cabbage',
              groups: imageSearch
                  ? const [
                      SearchCropGroup(title: 'Cabbage', terms: ['cabbage']),
                    ]
                  : const [],
              detectionConfidences: imageSearch
                  ? const [('Cabbage', 0.9)]
                  : const [],
              loadResults: (_) async => listings,
              loadFarms: () async => [],
              loadBuyerPosition: () async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Check freshness'), findsOneWidget);
        expect(find.text('Available Now'), findsOneWidget);
        expect(find.text('Soon to Harvest'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
