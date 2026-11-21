import 'dart:async';

import 'package:farmspot_app/models/insights.dart';
import 'package:farmspot_app/screens/insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const empty = InsightsPayload(
    sections: [],
    seasonalTrends: [],
    searchInterest: {'month': 'November', 'month_key': '2026-11'},
  );

  Future<void> open(
    WidgetTester tester,
    Future<InsightsPayload> Function() load,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: InsightsScreen(loadInsights: load),
      ),
    );
  }

  testWidgets('shows loading then empty data at 360 px with large text', (
    tester,
  ) async {
    final result = Completer<InsightsPayload>();
    await open(tester, () => result.future);
    expect(find.text('Loading crop insights…'), findsOneWidget);
    result.complete(empty);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Predicted for this month'), 130);
    expect(find.text('Predicted for this month'), findsOneWidget);
    expect(find.textContaining('Not enough data'), findsOneWidget);
  });

  testWidgets('shows a friendly error and retries', (tester) async {
    var attempts = 0;
    await open(tester, () async {
      if (++attempts == 1) throw StateError('offline');
      return empty;
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Check your connection'), findsOneWidget);
    final retry = find.text('Retry');
    await Scrollable.ensureVisible(tester.element(retry));
    await tester.pumpAndSettle();
    await tester.tap(retry.hitTestable());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Predicted for this month'), 130);
    expect(find.text('Predicted for this month'), findsOneWidget);
  });

  testWidgets('opens the evidence sheet for a long literal crop name', (
    tester,
  ) async {
    const name = '<b>Very long Philippine crop name with multiple words</b>';
    await open(
      tester,
      () async => const InsightsPayload(
        sections: [],
        seasonalTrends: [],
        searchInterest: {
          'month': 'November',
          'month_key': '2026-11',
          'predictions': [
            {
              'crop': name,
              'label': 'Likely seasonal',
              'confidence': 'Medium',
              'scores': {'trend': 0.1, 'current': 0.2},
              'reason': 'Search interest has risen recently.',
              'based_on': ['Nov 2025', 'last 30 days'],
              'history': {'October': 0.1, 'November': 0.2},
            },
          ],
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(360, 1400));
    final crop = find.text(name);
    await tester.pumpAndSettle();
    expect(crop, findsOneWidget);
    await Scrollable.ensureVisible(tester.element(crop), alignment: .1);
    await tester.pumpAndSettle();
    await tester.tap(crop.hitTestable());
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final scrollable = find.descendant(
      of: sheet,
      matching: find.byType(Scrollable),
    );
    final evidence = find.text('Past searches by month');
    await tester.scrollUntilVisible(evidence, 220, scrollable: scrollable);
    expect(evidence, findsOneWidget);
  });

  testWidgets('switches forecast months and explains missing history', (
    tester,
  ) async {
    await open(
      tester,
      () async => const InsightsPayload(
        sections: [],
        seasonalTrends: [],
        searchInterest: {
          'forecast': [
            {
              'month_key': '2026-12',
              'month': 'December 2026',
              'based_on': ['Dec 2025', 'Dec 2024'],
              'crops': [
                {'crop': 'Tomato'},
              ],
            },
            {
              'month_key': '2027-01',
              'month': 'January 2027',
              'based_on': [],
              'crops': [],
            },
          ],
        },
      ),
    );
    await tester.pumpAndSettle();
    final january = find.widgetWithText(ChoiceChip, 'Jan');
    await tester.scrollUntilVisible(january, 120);
    await Scrollable.ensureVisible(tester.element(january), alignment: .1);
    await tester.pumpAndSettle();
    expect(find.text('Tomato'), findsOneWidget);
    await tester.tap(january.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Tomato'), findsNothing);
    expect(find.textContaining('Too few past searches'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
