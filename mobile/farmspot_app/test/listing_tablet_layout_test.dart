import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';
import 'package:farmspot_app/widgets/search_widgets.dart';

void main() {
  for (final entry in {390.0: 2, 768.0: 3, 1024.0: 4}.entries) {
    testWidgets('home and search use ${entry.value} columns at ${entry.key}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(entry.key, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final crops = List.generate(
        9,
        (i) => CropListing(
          cropName: 'Fresh crop $i',
          farmName: 'Upland farm',
          status: 'AVAILABLE_NOW',
        ),
      );
      CropListing? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                CropLadderSliver(
                  listings: crops,
                  onTap: (crop) => selected = crop,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final cards = find.byType(CropCard);
      final y = tester.getTopLeft(cards.first).dy;
      for (var i = 0; i < entry.value; i++) {
        expect(tester.getTopLeft(cards.at(i)).dy, y);
      }
      expect(tester.getTopLeft(cards.at(entry.value)).dy, greaterThan(y));
      await tester.tap(cards.first);
      expect(selected, same(crops.first));
      expect(tester.takeException(), isNull);
      final cardWidth = tester.getSize(cards.first).width;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CropLadderSkeleton()),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(CropCardSkeleton).first).width,
        closeTo(cardWidth, 0.01),
      );
      expect(tester.takeException(), isNull);
      for (final imageResults in [false, true]) {
        SearchResultItem? tapped;
        final items = List.generate(
          9,
          (i) => SearchResultItem(
            crop: 'Crop $i',
            seller: 'Upland farm',
            distance: '0.4 km',
            status: imageResults ? 'AVAILABLE_NOW' : null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SearchResultGrid(
                  items: items,
                  cardAspectRatio: 0.72,
                  gap: 4,
                  onTap: (item) => tapped = item,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final results = find.byType(SearchResultCard);
        final top = tester.getTopLeft(results.first).dy;
        expect(tester.getTopLeft(results.at(entry.value - 1)).dy, top);
        expect(tester.getTopLeft(results.at(entry.value)).dy, greaterThan(top));
        await tester.tap(results.first);
        expect(tapped, same(items.first));
        expect(tester.takeException(), isNull);
      }
    });
  }
}
