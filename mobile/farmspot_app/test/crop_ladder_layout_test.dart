import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/widgets/home_widgets.dart';

// The Home feed "ladder" layout: rows of TWO cards. Inside each row the two
// cards are perfectly aligned (a real rung). The ladder movement happens
// BETWEEN rows: every row after the first one sits one step lower and one step
// right of the row above it — like stairs going down, but two-wide.

CropListing _sample(String name, {String farm = 'Farm'}) {
  return CropListing(
    cropName: name,
    farmName: farm,
    cropType: 'Vegetables',
    status: 'AVAILABLE_NOW',
    barangay: 'Sudlon II',
    postedLabel: 'today',
    expiresLabel: '3 days',
    distance: '0.4 km away',
    contactNumber: '09870000000',
  );
}

List<CropListing> _fiveItems() => [
      _sample('Tomato'),
      _sample('Cabbage'),
      _sample('Carrot'),
      _sample('Kangkong'),
      _sample('Ampalaya'),
    ];

Future<void> _pumpLadder(
  WidgetTester tester,
  double width, {
  List<CropListing>? items,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CropLadderGrid(
            listings: items ?? _fiveItems(),
            onTap: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('ladder grid: no overflow and renders every card',
      (tester) async {
    await _pumpLadder(tester, 360);

    expect(tester.takeException(), isNull, reason: 'no layout error');
    expect(find.byType(CropCard), findsNWidgets(5));
    expect(find.byType(CropLadderGrid), findsOneWidget);
  });

  testWidgets('first row: the two cards are perfectly aligned (tops level)',
      (tester) async {
    await _pumpLadder(tester, 360);

    final card0 = tester.getTopLeft(find.byType(CropCard).at(0));
    final card1 = tester.getTopLeft(find.byType(CropCard).at(1));

    // Same row, tops exactly level (no stagger inside a rung).
    expect(card1.dy, card0.dy);
    expect(card0.dx, greaterThanOrEqualTo(16));
    expect(card1.dx, greaterThan(card0.dx));
  });

  testWidgets('next rows shift right and drop lower (the ladder descent)',
      (tester) async {
    await _pumpLadder(tester, 360);

    final card0 = tester.getTopLeft(find.byType(CropCard).at(0));
    final card1 = tester.getTopLeft(find.byType(CropCard).at(1));
    final card2 = tester.getTopLeft(find.byType(CropCard).at(2));
    final card3 = tester.getTopLeft(find.byType(CropCard).at(3));

    // Row 2 sits BELOW row 1's level...
    expect(card2.dy, greaterThan(card0.dy));

    // ...and is indented to the right of the first row's left edge.
    expect(card2.dx, greaterThan(card0.dx));

    // Inside row 2 the pair stays aligned with each other (a single rung).
    expect(card3.dy, card2.dy);

    // The whole grid stays within the padded bounds.
    final right3 = tester.getTopRight(find.byType(CropCard).at(3)).dx;
    expect(right3, lessThanOrEqualTo(360 - 16));
  });

  testWidgets('odd total: cards still descend row by row top to bottom',
      (tester) async {
    await _pumpLadder(tester, 360);

    final card0 = tester.getTopLeft(find.byType(CropCard).at(0));
    final card2 = tester.getTopLeft(find.byType(CropCard).at(2));
    final card4 = tester.getTopLeft(find.byType(CropCard).at(4));

    expect(card2.dy, greaterThan(card0.dy));
    expect(card4.dy, greaterThan(card2.dy));
  });

  testWidgets('ladder grid handles a single card', (tester) async {
    await _pumpLadder(tester, 360, items: [_sample('Tomato')]);

    expect(tester.takeException(), isNull);
    expect(find.byType(CropCard), findsOneWidget);
  });

  testWidgets('ladder grid handles an empty list', (tester) async {
    await _pumpLadder(tester, 360, items: const []);

    expect(tester.takeException(), isNull);
    expect(find.byType(CropCard), findsNothing);
  });

  testWidgets('many cards stay on screen in descending rungs (20 cards)',
      (tester) async {
    await _pumpLadder(
      tester,
      360,
      items: List.generate(20, (i) => _sample('Crop $i', farm: 'Farm')),
    );

    expect(tester.takeException(), isNull, reason: 'no overflow with 20 cards');
    expect(find.byType(CropCard), findsNWidgets(20));

    for (var i = 0; i < 20; i++) {
      final top = tester.getTopLeft(find.byType(CropCard).at(i));
      final right = tester.getTopRight(find.byType(CropCard).at(i));
      expect(top.dx, greaterThanOrEqualTo(16));
      expect(right.dx, lessThanOrEqualTo(360 - 16));
      expect(top.dy, greaterThanOrEqualTo(16));
    }
  });
}