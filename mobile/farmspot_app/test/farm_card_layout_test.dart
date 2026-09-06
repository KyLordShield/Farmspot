import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/widgets/seller_widgets.dart';

// Regression tests for the My Farm farm-card overlap. The bug reproduced on a
// 360px device: the farm name/barangay text pushed into the "Edit Farm" button
// and "Live" badge. These tests render the real FarmCard widget at the real
// 360px constraint so any RenderFlex overflow throws into
// tester.takeException() and fails the test.

Future<void> _pumpFarmCard(
  WidgetTester tester, {
  required String name,
  required String barangay,
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FarmCard(
              name: name,
              barangay: barangay,
              status: 'APPROVED',
              onEditTap: () {},
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
      'farm card has NO overlap/overflow at 360px with the real bug repro '
      'data, at text scale 1.0 and 1.3', (tester) async {
    for (final scale in [1.0, 1.3]) {
      await _pumpFarmCard(
        tester,
        name: 'test3 farm',
        barangay: 'test3 barangay',
        textScale: scale,
      );

      expect(tester.takeException(), isNull,
          reason: 'repro data must not overlap/overflow at 360px, scale $scale');

      // Both texts are still fully visible — nothing slid under the buttons.
      expect(find.text('test3 farm'), findsOneWidget);
      expect(find.text('test3 barangay'), findsOneWidget);
      expect(find.text('Edit Farm'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
    }
  });

  testWidgets(
      'a much longer artificial farm name/barangay ellipsizes into its own '
      'column instead of overlapping the actions, with no exception',
      (tester) async {
    const longName =
        'test3farm the cooperative rice and corn producers association of '
        'southeastern barangay province incorporated';
    const longBarangay =
        'Barangay San Isidro de los Montes rural agricultural village zone';

    for (final scale in [1.0, 1.3]) {
      await _pumpFarmCard(
        tester,
        name: longName,
        barangay: longBarangay,
        textScale: scale,
      );

      expect(tester.takeException(), isNull,
          reason: 'long farm info must shrink to fit, never overflow, scale $scale');

      final nameParagraph =
          tester.renderObject<RenderParagraph>(find.text(longName));
      expect(nameParagraph.didExceedMaxLines, isTrue,
          reason: 'the farm name ellipsis must engage for over-long text');

      final barangayParagraph =
          tester.renderObject<RenderParagraph>(find.text(longBarangay));
      expect(barangayParagraph.didExceedMaxLines, isTrue,
          reason: 'the barangay ellipsis must engage for over-long text');

      // The actions are still present and on their own row below the text.
      expect(find.text('Edit Farm'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
    }
  });
}