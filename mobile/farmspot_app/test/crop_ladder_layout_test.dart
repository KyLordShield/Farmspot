import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/widgets/home_widgets.dart';

// The Home feed "ladder" layout: the first two cards sit side-by-side on one
// row, then every following card steps right like a ladder rung, wrapping back
// to the left edge before it would run off the right side.

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

  testWidgets('first two cards sit side by side on the same row',
      (tester) async {
    await _pumpLadder(tester, 360);

    final card0 = tester.getTopLeft(find.byType(CropCard).at(0));
    final card1 = tester.getTopLeft(find.byType(CropCard).at(1));

    // Same vertical position = same row.
    expect(card1.dy, card0.dy);

    // Card 1 is to the right of card 0.
    expect(card1.dx, greaterThan(card0.dx));

    // Both are inside the padded layout bounds.
    expect(card0.dx, greaterThanOrEqualTo(16));
    final right1 = tester.getTopRight(find.byType(CropCard).at(1)).dx;
    expect(right1, lessThanOrEqualTo(360 - 16));
  });

  testWidgets('ladder rungs step right then wrap back to the left',
      (tester) async {
    await _pumpLadder(tester, 360);

    final card0 = tester.getTopLeft(find.byType(CropCard).at(0));
    final card1 = tester.getTopLeft(find.byType(CropCard).at(1));
    final card2 = tester.getTopLeft(find.byType(CropCard).at(2));
    final card3 = tester.getTopLeft(find.byType(CropCard).at(3));
    final card4 = tester.getTopLeft(find.byType(CropCard).at(4));

    // Rung 1 (card 2): below the top row AND indented one step past the left
    // column, but still left of the top-right card.
    expect(card2.dy, greaterThan(card1.dy));
    expect(card2.dx, greaterThan(card0.dx));
    expect(card2.dx, lessThan(card1.dx));

    // Each next rung steps further right than the one before it.
    expect(card3.dx, greaterThan(card2.dx));
    expect(card3.dy, greaterThan(card2.dy));
    expect(card4.dx, greaterThan(card3.dx));

    // The step never pushes a card off the right edge.
    for (final card in [card0, card1, card2, card3, card4]) {
      expect(card.dx, greaterThanOrEqualTo(16));
      expect(card.dx, lessThanOrEqualTo(360 - 16));
    }

    // Cards descend: each consecutive card's top is lower than the one before.
    for (var i = 1; i <= 4; i++) {
      final prev = tester.getTopLeft(find.byType(CropCard).at(i - 1));
      final cur = tester.getTopLeft(find.byType(CropCard).at(i));
      expect(cur.dy, greaterThanOrEqualTo(prev.dy));
    }
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

  testWidgets('many rungs stay on screen (wraps back to the left)',
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