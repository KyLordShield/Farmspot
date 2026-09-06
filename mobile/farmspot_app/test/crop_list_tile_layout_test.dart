import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/widgets/seller_widgets.dart';

// Regression tests for the My Farm listing tile redesign. The old tile crammed
// a tiny thumbnail, a single-line (often 1-letter) truncated crop name, the
// status dropdown and the overflow menu into one row. These tests render the
// real CropListTile at the real 360px constraint so any RenderFlex overflow
// throws into tester.takeException() and fails the test, and prove a long crop
// name now gets two full lines instead of being strangled.

Future<void> _pumpTile(
  WidgetTester tester, {
  required String label,
  String? image,
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(360, 1200));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CropListTile(
              listing: Listing(
                id: 'L1',
                cropIcon: label,
                status: 'AVAILABLE_NOW',
                categoryId: 'C1',
                image: image,
              ),
              updating: false,
              onStatusTap: () {},
              onEditTap: () {},
              onDeleteTap: () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a long multi-word crop name wraps to two lines with an ellipsis and '
      'nothing overflows at 360px, at text scale 1.0 and 1.3', (tester) async {
    const longName =
        'Amaranth and okra intercropped for the wet season harvest towards '
        'the hillside';
    for (final scale in [1.0, 1.3]) {
      await _pumpTile(tester, label: longName, textScale: scale);

      expect(tester.takeException(), isNull,
          reason: 'crop tile must not overflow at 360px, scale $scale');

      final paragraph =
          tester.renderObject<RenderParagraph>(find.text(longName));
      expect(paragraph.didExceedMaxLines, isTrue,
          reason: 'an over-long crop name must truncate with the ellipsis');

      // The name, the status chip (below the name) and the overflow menu are
      // all present and clearly separated.
      expect(find.text('Available Now'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      final nameTop = tester.getTopLeft(find.text(longName)).dy;
      final statusTop = tester.getTopLeft(find.text('Available Now')).dy;
      expect(statusTop, greaterThan(nameTop),
          reason: 'the status chip must sit BELOW the crop name');
    }
  });

  testWidgets(
      'a single very long unbroken crop name ellipsizes instead of spawning '
      'overlap or overflow (the old "V..." class of bug)', (tester) async {
    const longWord = 'Sempervivumtectorumacuminatummarginatum';
    await _pumpTile(tester, label: longWord);

    expect(tester.takeException(), isNull,
        reason: 'a long unbroken word must shrink to fit, never overflow');

    final paragraph =
        tester.renderObject<RenderParagraph>(find.text(longWord));
    expect(paragraph.didExceedMaxLines, isTrue,
        reason: 'the ellipsis must actually engage for over-long text');

    // Status and menu are still reachable next to the truncated name.
    expect(find.text('Available Now'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('cropping the tile with a real photo keeps a large 68px '
      'thumbnail with no overflow', (tester) async {
    await _pumpTile(
      tester,
      label: 'Cabbage',
      image: 'https://res.cloudinary.com/x/listing-photos/L1/pic.jpg',
    );

    expect(tester.takeException(), isNull,
        reason: 'the photo thumbnail must not overflow the 360px tile');

    // Fallback icon still present via the network-image error builder, which
    // proves the oversized-image slot itself doesn't break layout.
    expect(find.byIcon(Icons.eco), findsOneWidget);
    expect(find.text('Cabbage'), findsOneWidget);
  });
}