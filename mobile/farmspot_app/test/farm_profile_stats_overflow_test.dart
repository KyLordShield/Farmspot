import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/screens/farm_profile_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

// Regression tests for the stats-row overflow under the farm banner. The bug
// reproduced on a 360px phone with the distance stat ("0.4 km away from you")
// overflowing the row by 18px. These tests render the real widget at the real
// 360px constraint (not just asserting text presence) so a RenderFlex overflow
// throws into tester.takeException() and fails the test, unlike the earlier
// overflow bugs that slipped past presence-only assertions.

CropListing _crop(String status, {required String distance}) => CropListing(
      cropName: 'Cabbage',
      farmName: 'Mr. A Farm',
      cropType: 'Vegetables',
      status: status,
      farmId: 'FRMA',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: distance,
      contactNumber: '09870000000',
    );

FarmProfileData _profile({required String distance}) => FarmProfileData(
      id: 'FRMA',
      name: 'Mr. A Farm',
      barangay: 'Sudlon II',
      status: 'APPROVED',
      listings: [
        _crop('AVAILABLE_NOW', distance: distance),
        _crop('AVAILABLE_NOW', distance: distance),
        _crop('SOON_TO_HARVEST', distance: distance),
      ],
    );

Future<void> _pump(
  WidgetTester tester,
  String distance, {
  double textScale = 1.0,
}) async {
  // Phone width from the bug repro screenshot; tall so tabs don't clip.
  await tester.binding.setSurfaceSize(const Size(360, 1200));
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      home: FarmProfileScreen(
        farmId: 'FRMA',
        initialData: _profile(distance: distance),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'stats row has NO overflow banner at 360px with the real "0.4 km away" '
      'distance, at text scale 1.0 and 1.3', (tester) async {
    for (final scale in [1.0, 1.3]) {
      await _pump(tester, '0.4 km away', textScale: scale);

      // A RenderFlex overflow reports through the test binding; returning null
      // here is exactly what proves the yellow/black banner is gone.
      expect(tester.takeException(), isNull,
          reason: 'stats row must not overflow at 360px, text scale $scale');

      // The real distance string is still displayed.
      expect(find.text('0.4 km away'), findsOneWidget);
    }
  });

  testWidgets(
      'a too-long distance string truncates with an ellipsis instead of '
      'overflowing the row, and no exception is raised', (tester) async {
    const longDistance =
        '210 kilometers away from the farm on the hillside edge';
    await _pump(tester, longDistance);

    expect(tester.takeException(), isNull,
        reason: 'an overly long distance must shrink to fit, never overflow');

    final paragraph =
        tester.renderObject<RenderParagraph>(find.text(longDistance));
    expect(paragraph.didExceedMaxLines, isTrue,
        reason: 'the ellipsis must actually engage for over-long text');
  });
}