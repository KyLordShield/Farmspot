import 'package:farmspot_app/models/crop_category.dart';
import 'package:farmspot_app/models/home_filters.dart';
import 'package:farmspot_app/theme.dart';
import 'package:farmspot_app/widgets/home_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A mutable box for the sheet's return value.
class _Applied {
  HomeFilters? value;
}

/// The home feed's Filter button and the sheet behind it.
///
/// The button is tested as a widget rather than through HomeScreen because the
/// screen loads its feed over HTTP, which makes a widget test of the whole
/// screen depend on a live backend. The button and sheet hold all the logic
/// worth pinning down on their own.
void main() {
  final categories = [
    CropCategory(id: 'LEAFVG', name: 'Leafy Vegetables', icon: 'spa'),
    CropCategory(id: 'ROOTCP', name: 'Root Crops', icon: 'agriculture'),
  ];

  Future<void> pumpButton(
    WidgetTester tester,
    HomeFilters filters, {
    VoidCallback? onTap,
    String? categoryName,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: HomeFilterButton(
            filters: filters,
            onTap: onTap ?? () {},
            categoryName: categoryName,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Holds whatever the sheet's Apply button returned, so a test can assert on
  /// the value the screen would actually receive. A box rather than a closure
  /// because the value only exists after the test does the tapping.
  final applied = _Applied();

  /// Opens the sheet, with [applied] wired to its return value.
  Future<void> pumpSheet(
    WidgetTester tester, {
    required HomeFilters initial,
  }) async {
    applied.value = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                applied.value = await showHomeFilterSheet(
                  context,
                  current: initial,
                  categories: categories,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('the filter button', () {
    testWidgets('reads quietly when nothing is applied', (tester) async {
      await pumpButton(tester, HomeFilters.none);

      expect(find.text('Filter'), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == const Color(0xFFE3EEDD),
        ),
        findsWidgets,
        reason: 'the quiet green fill',
      );
    });

    testWidgets('shows an active state once anything is applied', (
      tester,
    ) async {
      await pumpButton(
        tester,
        const HomeFilters(availability: FeedAvailability.availableNow),
      );

      // Only the ordering changed, which still has to be visible: otherwise a
      // buyer cannot tell the feed is no longer in its default order.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == const Color(0xFFFDF3E0),
        ),
        findsWidgets,
        reason: 'the active amber fill',
      );
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('is tappable', (tester) async {
      var taps = 0;
      await pumpButton(tester, HomeFilters.none, onTap: () => taps++);

      await tester.tap(find.byKey(HomeFilterButton.buttonKey));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('carries an accessible label naming what is applied', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpButton(
        tester,
        const HomeFilters(
          availability: FeedAvailability.soonToHarvest,
          sort: HomeSortMode.popular,
        ),
      );

      final node = tester.getSemantics(find.byKey(HomeFilterButton.buttonKey));
      expect(node.label, contains('Soon to harvest'));
      expect(node.label, contains('Most popular'));

      // Disposed here rather than in a tearDown: the framework checks for a
      // leaked handle at the end of the test body, which runs first.
      handle.dispose();
    });

    testWidgets('names the applied category in its label', (tester) async {
      final handle = tester.ensureSemantics();
      // The category chips that used to name the selected category on screen
      // are gone, so if this label did not name it the applied category would
      // be invisible without reopening the sheet.
      await pumpButton(
        tester,
        const HomeFilters(categoryId: 'LEAFVG'),
        categoryName: 'Leafy Vegetables',
      );

      final node = tester.getSemantics(find.byKey(HomeFilterButton.buttonKey));
      expect(node.label, contains('Leafy Vegetables'));
      expect(node.label, isNot(contains('1 category')));

      handle.dispose();
    });

    testWidgets('does not overflow on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpButton(
        tester,
        const HomeFilters(
          categoryId: 'LEAFVG',
          availability: FeedAvailability.availableNow,
          sort: HomeSortMode.popular,
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  /// Scrolls the sheet's option list until [label] is on screen.
  ///
  /// The list is a lazy ListView, so the sort options sit below the fold and are
  /// not built at all until scrolled to — a bare find.text would report 0 for
  /// them and quietly turn three assertions into no-ops.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    final list = find.descendant(
      of: find.byType(HomeFilterSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.text(label), 60, scrollable: list);
    await tester.pumpAndSettle();
  }

  /// Scrolls to [label] and taps it.
  Future<void> tapOption(WidgetTester tester, String label) async {
    await scrollTo(tester, label);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('the filter sheet', () {
    testWidgets('offers all three groups and every option', (tester) async {
      await pumpSheet(tester, initial: HomeFilters.none);

      expect(find.text('CATEGORY'), findsOneWidget);
      expect(find.text('All categories'), findsOneWidget);
      expect(find.text('Leafy Vegetables'), findsOneWidget);
      expect(find.text('Root Crops'), findsOneWidget);
      expect(find.text('AVAILABILITY'), findsOneWidget);
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('Available now'), findsOneWidget);
      expect(find.text('Soon to harvest'), findsOneWidget);

      // The sort group is below the fold, so it only exists after scrolling.
      await scrollTo(tester, 'SORT BY');
      expect(find.text('Latest'), findsOneWidget);
      expect(find.text('By harvest date'), findsOneWidget);
      expect(find.text('Most popular'), findsOneWidget);
    });

    testWidgets('stays open while options are picked, and applies on tap', (
      tester,
    ) async {
      await pumpSheet(tester, initial: HomeFilters.none);

      // A sheet that closed on the first tap would need reopening twice more
      // for availability and sort.
      await tapOption(tester, 'Root Crops');
      expect(find.text('Root Crops'), findsOneWidget);

      await tapOption(tester, 'Available now');
      expect(find.text('Available now'), findsOneWidget);

      await tapOption(tester, 'Most popular');
      expect(find.text('Most popular'), findsOneWidget);

      expect(find.text('Apply filters'), findsOneWidget);
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();

      final result = applied.value;
      expect(result, isNotNull);
      expect(result!.categoryId, 'ROOTCP');
      expect(result.availability, FeedAvailability.availableNow);
      expect(result.sort, HomeSortMode.popular);
    });

    testWidgets('dismissing the sheet returns nothing', (tester) async {
      await pumpSheet(tester, initial: HomeFilters.none);

      // Tapping the scrim is how a buyer backs out without applying.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(applied.value, isNull);
    });

    testWidgets('the button says Done when nothing was changed', (
      tester,
    ) async {
      await pumpSheet(tester, initial: HomeFilters.none);

      expect(find.text('Apply filters'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('Reset appears only after a change, and clears everything', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        initial: const HomeFilters(sort: HomeSortMode.popular),
      );

      // Filters are already applied, so there is something to clear — and
      // because nothing has been touched yet, the button still says Done.
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tapOption(tester, 'Available now');
      expect(find.text('Apply filters'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      // The draft is now empty, so there is nothing left to reset.
      expect(find.text('Reset'), findsNothing);
      // But it is still a change from what was applied, so it still has to be
      // confirmed rather than silently applied.
      expect(find.text('Apply filters'), findsOneWidget);

      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(applied.value, HomeFilters.none);
    });

    testWidgets('round-trips filters that were already applied', (
      tester,
    ) async {
      const initial = HomeFilters(
        categoryId: 'LEAFVG',
        availability: FeedAvailability.soonToHarvest,
        sort: HomeSortMode.date,
      );
      await pumpSheet(tester, initial: initial);

      // The two visible groups show their picks. Sort sits further down the
      // list, so it is checked by the round trip below instead.
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Nothing was touched, so the screen must receive the identical value
      // and be able to skip a pointless reload.
      expect(applied.value, initial);
    });

    testWidgets('clearing one group leaves the others alone', (tester) async {
      await pumpSheet(
        tester,
        initial: const HomeFilters(
          categoryId: 'LEAFVG',
          availability: FeedAvailability.soonToHarvest,
          sort: HomeSortMode.popular,
        ),
      );

      await tapOption(tester, 'Any');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();

      final result = applied.value!;
      expect(result.availability, isNull);
      expect(result.categoryId, 'LEAFVG');
      expect(result.sort, HomeSortMode.popular);
    });

    testWidgets('fits a short screen without overflowing', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 480 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpSheet(tester, initial: HomeFilters.none);

      expect(tester.takeException(), isNull);
      // The Apply row is the thing that must survive being pushed off screen.
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('HomeFilters', () {
    test('is inactive until something is set', () {
      expect(HomeFilters.none.isActive, isFalse);
      expect(HomeFilters.none.summaryFor(), isNull);

      expect(const HomeFilters(categoryId: 'LEAFVG').isActive, isTrue);
      expect(
        const HomeFilters(availability: FeedAvailability.availableNow).isActive,
        isTrue,
      );
      // Re-sorting alone counts as active.
      expect(const HomeFilters(sort: HomeSortMode.popular).isActive, isTrue);
    });

    test('only availability needs a refetch', () {
      // Category is filtered locally by the chips, so sending it to the server
      // would narrow the same feed twice.
      expect(const HomeFilters(categoryId: 'LEAFVG').needsRefetch, isFalse);
      expect(const HomeFilters(sort: HomeSortMode.date).needsRefetch, isFalse);
      expect(
        const HomeFilters(
          availability: FeedAvailability.availableNow,
        ).needsRefetch,
        isTrue,
      );
    });

    test('compares by value so an unchanged sheet is a no-op', () {
      expect(
        const HomeFilters(categoryId: 'LEAFVG', sort: HomeSortMode.popular),
        equals(
          const HomeFilters(categoryId: 'LEAFVG', sort: HomeSortMode.popular),
        ),
      );
      expect(
        const HomeFilters(categoryId: 'LEAFVG'),
        isNot(equals(const HomeFilters(categoryId: 'ROOTCP'))),
      );
    });

    test('copyWith can set and clear each group', () {
      final base = const HomeFilters(
        categoryId: 'LEAFVG',
        availability: FeedAvailability.availableNow,
        sort: HomeSortMode.date,
      );

      expect(base.copyWith(clearCategory: true).categoryId, isNull);
      // Clearing one group must not wipe the others.
      expect(
        base.copyWith(clearCategory: true).availability,
        FeedAvailability.availableNow,
      );
      expect(base.copyWith(clearAvailability: true).categoryId, 'LEAFVG');
      expect(
        base.copyWith(sort: HomeSortMode.latest).sort,
        HomeSortMode.latest,
      );
    });

    test('summarises what is applied', () {
      expect(
        const HomeFilters(
          categoryId: 'LEAFVG',
          availability: FeedAvailability.soonToHarvest,
          sort: HomeSortMode.popular,
        ).summaryFor(categoryName: 'Leafy Vegetables'),
        'Leafy Vegetables • Soon to harvest • Most popular',
      );
      // The default sort is not worth showing: it is what the feed already
      // does, and printing it would make every filtered chip look busier.
      expect(
        const HomeFilters(
          categoryId: 'LEAFVG',
        ).summaryFor(categoryName: 'Leafy Vegetables'),
        'Leafy Vegetables',
      );
    });

    test('falls back to a count when the category name is not resolved', () {
      // The name is looked up from the category list, which may not have
      // loaded yet. Saying how many rather than showing a blank beats showing
      // nothing at all.
      expect(
        const HomeFilters(categoryId: 'LEAFVG').summaryFor(),
        '1 category',
      );
    });

    test('wire values are the ones the backend whitelist expects', () {
      expect(HomeSortMode.latest.wireValue, 'latest');
      expect(HomeSortMode.date.wireValue, 'date');
      expect(HomeSortMode.popular.wireValue, 'popular');
      expect(FeedAvailability.availableNow.wireValue, 'AVAILABLE_NOW');
      expect(FeedAvailability.soonToHarvest.wireValue, 'SOON_TO_HARVEST');
    });
  });
}
