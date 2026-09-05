import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/theme.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

// Why the OLD tests missed the real-device overflow: the grid used a FIXED
// childAspectRatio (an assumed constant content height), and the test font
// (Flutter's Ahem) lays out every glyph with line boxes exactly fontSize tall.
// A physical device renders real fonts with taller line metrics, so the fixed
// ratio's baked-in height was a few px short of live content. These tests make
// that impossible to miss again:
//   * the masonry grid sizes each card to its OWN rendered content (no fixed
//     ratio exists to under-size anything);
//   * assertions run at text scale 1.0 AND 1.3 (simulating device /
//     accessibility line-height differences) while checking rendered box
//     geometry and RenderParagraph.didExceedMaxLines against real boxes.

// Must fit 2 card-lines at EVERY tested width (360/1280) and scale (1.0/1.3):
// the test font renders glyphs as full-size squares, so it must be word-broken
// conservatively (2 short words) to guarantee it is one that displays fully.
const _twoLineName = 'Fresh Corn';
const _nameForStagger = 'Sweet Corn Harvest'; // 2-3 lines -> taller card
const _extremeName =
    'Extraordinarily long name of a crop that a farmer typed without any word '
    'boundaries to help the layout engines wrap it gracefully somewhere';

CropListing _sample({
  required String name,
  required String farm,
  String status = 'AVAILABLE_NOW',
}) {
  return CropListing(
    cropName: name,
    farmName: farm,
    cropType: 'Vegetables',
    status: status,
    barangay: 'Sudlon II',
    postedLabel: 'today',
    expiresLabel: '3 days',
    distance: '0.4 km away',
    contactNumber: '09870000000',
  );
}

List<CropListing> _mixedItems() => [
      _sample(name: _nameForStagger, farm: 'Farm A'), // taller card
      _sample(name: 'Cabbage', farm: 'Farm B', status: 'SOON_TO_HARVEST'),
      _sample(name: 'Carrot', farm: _extremeName, status: 'NOT_AVAILABLE'),
      _sample(name: 'Kangkong', farm: 'Farm D'),
    ];

Future<void> _pumpGrid(
  WidgetTester tester,
  double width,
  List<CropListing> items, {
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1200));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CropCardGrid(
            listings: items,
            onTap: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final width in [360.0, 1280.0]) {
    final label = width == 360 ? 'narrow phone' : 'wide desktop';

    testWidgets('masonry grid: no overflow, 2 cols, tight 8px spacing ($label)',
        (tester) async {
      await _pumpGrid(tester, width, _mixedItems());

      expect(tester.takeException(), isNull,
          reason: 'no overflow/layout error at $width');
      expect(find.byType(MasonryGridView), findsOneWidget);
      expect(find.byType(CropCard), findsNWidgets(4));

      final card0 = tester.getTopLeft(find.byType(CropCard).at(0));
      final card1 = tester.getTopLeft(find.byType(CropCard).at(1));

      // Two columns: first two cards sit side-by-side (same row).
      expect(card1.dy, card0.dy);

      // Tight cross-axis spacing: gap between the two top cards is exactly 8.
      final right0 = tester.getTopRight(find.byType(CropCard).at(0)).dx;
      final left1 = tester.getTopLeft(find.byType(CropCard).at(1)).dx;
      expect(left1 - right0, 8);

      // Staggered, not uniform rows: a 2-line-name card is taller than its
      // 1-line neighbor, and the columns flow independently (col1 bottom lower
      // than col0 bottom after the extra items pack into the shorter column).
      final h0 = tester.getSize(find.byType(CropCard).at(0)).height;
      final h1 = tester.getSize(find.byType(CropCard).at(1)).height;
      expect(h0, greaterThan(h1),
          reason: '2-line name must make card 0 taller than card 1');

      final bottom0 =
          tester.getBottomLeft(find.byType(CropCard).at(0)).dy;
      final bottom3 = tester.getBottomLeft(find.byType(CropCard).at(3)).dy;
      expect(bottom3, greaterThan(bottom0),
          reason: 'columns must pack independently (ladder look)');

      // Vertical spacing between two items stacked in the same column is 8.
      if (tester.getTopLeft(find.byType(CropCard).at(1)).dx ==
          tester.getTopLeft(find.byType(CropCard).at(2)).dx) {
        expect(
          tester.getTopLeft(find.byType(CropCard).at(2)).dy -
              tester.getBottomLeft(find.byType(CropCard).at(1)).dy,
          8,
        );
      }

      // Human labels, never the raw enum.
      expect(find.text('Available Now'), findsWidgets);
      expect(find.text('Soon to Harvest'), findsOneWidget);
      expect(find.text('Not Available'), findsOneWidget);
      expect(find.text('AVAILABLE_NOW'), findsNothing);
      expect(find.text('SOON_TO_HARVEST'), findsNothing);
      expect(find.text('NOT_AVAILABLE'), findsNothing);
    });

    testWidgets(
        'no overflow + full 2-line names at text scale 1.0 and 1.3 ($label)',
        (tester) async {
      for (final scale in [1.0, 1.3]) {
        await _pumpGrid(tester, width, [
          _sample(name: _twoLineName, farm: 'Farm A'),
          _sample(name: _twoLineName, farm: 'Farm B'),
        ], textScale: scale);

        // A real renderer overflow would surface here (this is what the old
        // fixed-ratio layout did on device fonts at scale ~1.0+).
        expect(tester.takeException(), isNull,
            reason: 'text scale $scale at $width must not overflow');

        // The 2-line-able name must fully render (never truncated): maxLines 2
        // configured AND the paragraph did not exceed it.
        final nameText = tester.widget<Text>(
          find.text(_twoLineName).first,
        );
        expect(nameText.maxLines, 2);
        expect(nameText.overflow, TextOverflow.ellipsis);
        final para = tester.renderObject<RenderParagraph>(
          find.text(_twoLineName).first,
        );
        expect(para.didExceedMaxLines, isFalse,
            reason: '$label at scale $scale must show 2 full name lines');

        // An extreme name still truncates (no hard overflow), so long names can
        // never explode the card edge.
        await _pumpGrid(tester, width, [
          _sample(name: _extremeName, farm: 'Farm A'),
        ], textScale: scale);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('status badge uses the status color ($label)', (tester) async {
      await _pumpGrid(tester, width, [
        _sample(name: 'Cabbage', farm: 'Farm A'),
      ]);

      final badgeContainer = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Available Now'),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.decoration is BoxDecoration,
              ),
            )
            .first,
      );
      final decoration = badgeContainer.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.primaryGreen);
    });
  }

  testWidgets('tapping a grid card opens the detail screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: CropCardGrid(
              listings: [_sample(name: 'Tomato', farm: 'Farm A')],
              onTap: (l) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailScreen(listing: l),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Tomato'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductDetailScreen), findsOneWidget);
    expect(find.text('Tomato'), findsOneWidget); // detail headline
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}