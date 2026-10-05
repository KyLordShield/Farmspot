import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:latlong2/latlong.dart';

import 'package:farmspot_app/models/farm_pin.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/models/search_crop_group.dart';
import 'package:farmspot_app/screens/search_results_screen.dart';
import 'package:farmspot_app/services/location_service.dart';
import 'package:farmspot_app/widgets/search_widgets.dart';

/// Buyer position used by the fixtures: Cebu City.
const _userPos = LatLng(10.3178, 123.8742);

Listing _listing(
  String id,
  String crop,
  String farm, {
  String status = 'AVAILABLE_NOW',
  String? farmId,
}) {
  return Listing(
    id: id,
    cropIcon: crop,
    farmName: farm,
    farmId: farmId,
    status: status,
    categoryName: 'Vegetables',
  );
}

FarmPin _pin(String id, double lat, double lon) {
  return FarmPin(id: id, name: 'Farm $id', latitude: lat, longitude: lon);
}

/// Puts [result] on a farm [kmDueNorth] of the buyer. Used to build a set of
/// farms at known distances so the nearest-first ordering is checkable.
FarmPin _pinKmNorth(String id, double kmDueNorth) {
  // 1 degree of latitude is ~111.32 km, so this lands the pin at the wanted
  // distance without depending on the haversine implementation under test.
  final lat = _userPos.latitude + kmDueNorth / 111.32;
  return _pin(id, lat, _userPos.longitude);
}

void main() {
  group('Haversine distance', () {
    test('is zero for identical points', () {
      expect(LocationService.distanceKm(_userPos, _userPos), 0);
    });

    test('matches a known Cebu City distance within tolerance', () {
      // Cebu City -> Mandaue is roughly 8 km, so this checks the formula
      // against a real-world distance rather than a round trip of itself.
      const mandaue = LatLng(10.3236, 123.8922);
      final km = LocationService.distanceKm(_userPos, mandaue);
      expect(km, closeTo(1.9, 0.6));
    });

    test('is symmetric', () {
      const other = LatLng(10.5, 124.0);
      expect(
        LocationService.distanceKm(_userPos, other),
        closeTo(LocationService.distanceKm(other, _userPos), 1e-9),
      );
    });

    test('grows with separation', () {
      const near = LatLng(10.32, 123.88);
      const far = LatLng(10.60, 124.10);
      expect(
        LocationService.distanceKm(_userPos, near),
        lessThan(LocationService.distanceKm(_userPos, far)),
      );
    });
  });

  group('mixed image-search list', () {
    Future<void> pumpImageSearch(
      WidgetTester tester, {
      required List<SearchCropGroup> groups,
      required List<(String, double)> confidences,
      required Future<List<Listing>> Function(String term) loadResults,
      List<FarmPin> farms = const [],
      LatLng? location = _userPos,
      bool hasLocation = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsScreen(
            query: groups.isEmpty ? '' : groups.first.title,
            groups: groups,
            detectionConfidences: confidences,
            loadResults: loadResults,
            loadFarms: () async => farms,
            loadBuyerPosition: () async => hasLocation ? location : null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    const chayoteGroup = SearchCropGroup(
      title: 'Chayote',
      terms: ['chayote', 'sayote'],
    );
    const cabbageGroup = SearchCropGroup(
      title: 'Cabbage',
      terms: ['cabbage', 'repolyo'],
    );
    const bokChoyGroup = SearchCropGroup(
      title: 'Bok choy',
      terms: ['bok choy', 'pechay'],
    );

    testWidgets('mixes every detected crop into one list, no crop headers', (
      tester,
    ) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup, cabbageGroup, bokChoyGroup],
        confidences: const [
          ('Chayote', 0.91),
          ('Cabbage', 0.82),
          ('Bok choy', 0.64),
        ],
        loadResults: (term) async => switch (term) {
          'chayote' => [_listing('L1', 'Chayote', 'A Farm', farmId: 'F1')],
          'sayote' => [_listing('L1', 'Chayote', 'A Farm', farmId: 'F1')],
          'cabbage' => [_listing('L2', 'Cabbage', 'B Farm', farmId: 'F2')],
          'repolyo' => [_listing('L2', 'Cabbage', 'B Farm', farmId: 'F2')],
          _ => [_listing('L3', 'Bok choy', 'C Farm', farmId: 'F3')],
        },
        farms: [
          _pinKmNorth('F1', 1.0),
          _pinKmNorth('F2', 2.0),
          _pinKmNorth('F3', 3.0),
        ],
      );

      // All three crops present in the one list.
      expect(find.text('A Farm'), findsOneWidget);
      expect(find.text('B Farm'), findsOneWidget);
      expect(find.text('C Farm'), findsOneWidget);

      // A single "3 crops found" summary, not one header per crop.
      expect(find.text('3 crops found in your photo'), findsOneWidget);
      // No crop section headers from the old grouped layout.
      expect(find.text('Near you'), findsNothing);
      expect(find.text('Other farms'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    // Result cards sit in a 2-column grid, so two cards in the same visual
    // row share a dy and are ordered left-to-right by dx. Comparing only dy
    // makes "which card is first" meaningless, so compare (row, column).
    int orderingOf(WidgetTester tester, String text) {
      final at = tester.getTopLeft(find.text(text));
      // Cards are laid out in rows of two, so fold dy into a row band.
      return at.dy.round() * 10000 + at.dx.round();
    }

    testWidgets('orders nearest farm first and shows the distance', (
      tester,
    ) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup, cabbageGroup],
        confidences: const [('Chayote', 0.5), ('Cabbage', 0.9)],
        loadResults: (term) async => switch (term) {
          // Deliberately return the FAR farm first for the stronger crop so a
          // confidence-ordered list would be wrong.
          'chayote' => [_listing('L1', 'Chayote', 'Far Farm', farmId: 'F9')],
          'sayote' => const [],
          'cabbage' => [_listing('L2', 'Cabbage', 'Near Farm', farmId: 'F1')],
          _ => const [],
        },
        farms: [_pinKmNorth('F9', 8.0), _pinKmNorth('F1', 1.0)],
      );

      expect(
        orderingOf(tester, 'Near Farm'),
        lessThan(orderingOf(tester, 'Far Farm')),
        reason: 'nearest farm should render first',
      );

      // Real distance text, meters under 1 km.
      expect(find.textContaining('km away'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a listing matched by two crops appears only once', (
      tester,
    ) async {
      // L1 comes back for BOTH groups' alias terms. It must render exactly
      // once even though two crops matched it.
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup, cabbageGroup],
        confidences: const [('Chayote', 0.4), ('Cabbage', 0.9)],
        loadResults: (term) async => [
          _listing('L1', 'Chayote', 'Shared Farm', farmId: 'F1'),
        ],
        farms: [_pinKmNorth('F1', 1.0)],
      );

      expect(find.text('Shared Farm'), findsOneWidget);
      expect(find.byType(SearchResultCard), findsOneWidget);
      // The winning crop's confidence is used for ranking but never shown.
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cards show the availability badge, never a confidence chip', (
      tester,
    ) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup],
        confidences: const [('Chayote', 0.86)],
        loadResults: (term) async => [
          _listing(
            'L1',
            'Chayote',
            'Ready Farm',
            status: 'AVAILABLE_NOW',
            farmId: 'F1',
          ),
          _listing(
            'L2',
            'Chayote',
            'Later Farm',
            status: 'SOON_TO_HARVEST',
            farmId: 'F2',
          ),
        ],
        farms: [_pinKmNorth('F1', 1.0), _pinKmNorth('F2', 2.0)],
      );

      // Same labels, same top-left placement as the Home grid.
      expect(find.text('Available Now'), findsOneWidget);
      expect(find.text('Soon to Harvest'), findsOneWidget);

      for (final (label, farm, index) in [
        ('Available Now', 'Ready Farm', 0),
        ('Soon to Harvest', 'Later Farm', 1),
      ]) {
        final badgeTopLeft = tester.getTopLeft(find.text(label));
        final cardTopLeft = tester.getTopLeft(
          find.byType(SearchResultCard).at(index),
        );
        final cardBottomRight = tester.getBottomRight(
          find.byType(SearchResultCard).at(index),
        );

        // Top-left of the photo area, same as the Home grid badge.
        expect(badgeTopLeft.dy, greaterThan(cardTopLeft.dy));
        // Inside the photo and left-aligned, matching the Home grid badge.
        expect(badgeTopLeft.dx, greaterThan(cardTopLeft.dx));
        expect(
          badgeTopLeft.dx,
          lessThan((cardTopLeft.dx + cardBottomRight.dx) / 2),
        );
        // Sits above the crop/farm text rather than in the footer.
        expect(
          badgeTopLeft.dy,
          lessThan(tester.getTopLeft(find.text(farm)).dy),
        );
      }
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the count line uses the image range, not the text-search one',
      (tester) async {
        await pumpImageSearch(
          tester,
          groups: const [chayoteGroup],
          confidences: const [('Chayote', 0.8)],
          loadResults: (term) async => [
            _listing('L1', 'Chayote', 'Near Farm', farmId: 'F1'),
          ],
          farms: [_pinKmNorth('F1', 1.0)],
        );

        // It must not contradict the 10 km divider sitting below it.
        expect(find.textContaining('within 10 km of you'), findsOneWidget);
        expect(find.textContaining('within 15 km of you'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('places the range divider after the last in-range result', (
      tester,
    ) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup],
        confidences: const [('Chayote', 0.8)],
        loadResults: (term) async => switch (term) {
          'chayote' => [
            _listing('L1', 'Chayote', 'Near Farm', farmId: 'F1'),
            _listing('L2', 'Chayote', 'Far Farm', farmId: 'F9'),
          ],
          _ => const [],
        },
        // 2 km is inside the 10 km range; 40 km is well outside it.
        farms: [_pinKmNorth('F1', 2.0), _pinKmNorth('F9', 40.0)],
      );

      // Divider text is built from the constant, never hardcoded.
      expect(
        find.text('Farms beyond this point are more than 10 km away'),
        findsOneWidget,
      );

      final dividerY = tester
          .getTopLeft(find.textContaining('Farms beyond this point'))
          .dy;
      expect(tester.getTopLeft(find.text('Near Farm')).dy, lessThan(dividerY));
      expect(dividerY, lessThan(tester.getTopLeft(find.text('Far Farm')).dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('when nothing is in range the divider is at the top and far '
        'results still show', (tester) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup],
        confidences: const [('Chayote', 0.8)],
        loadResults: (term) async => switch (term) {
          'chayote' => [
            _listing('L1', 'Chayote', 'Far One', farmId: 'F8'),
            _listing('L2', 'Chayote', 'Far Two', farmId: 'F9'),
          ],
          _ => const [],
        },
        farms: [_pinKmNorth('F8', 30.0), _pinKmNorth('F9', 50.0)],
      );

      final dividerY = tester
          .getTopLeft(find.textContaining('Farms beyond this point'))
          .dy;
      expect(dividerY, lessThan(tester.getTopLeft(find.text('Far One')).dy));
      // Still sorted nearest-first, and still shown.
      expect(
        orderingOf(tester, 'Far One'),
        lessThan(orderingOf(tester, 'Far Two')),
      );
      expect(find.text('Far One'), findsOneWidget);
      expect(find.text('Far Two'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without location: confidence order, note shown, no divider', (
      tester,
    ) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup, cabbageGroup],
        confidences: const [('Chayote', 0.3), ('Cabbage', 0.95)],
        // Reverse alphabetical farm names so confidence order is
        // distinguishable from any name-based ordering.
        loadResults: (term) async => switch (term) {
          'chayote' => [_listing('L1', 'Chayote', 'Alpha Farm', farmId: 'F1')],
          'sayote' => const [],
          'cabbage' => [_listing('L2', 'Cabbage', 'Zulu Farm', farmId: 'F2')],
          _ => const [],
        },
        farms: [_pinKmNorth('F1', 9.0), _pinKmNorth('F2', 1.0)],
        hasLocation: false,
      );

      expect(
        find.text('Turn on location to see the closest farms first.'),
        findsOneWidget,
      );
      // No divider, and no distances at all.
      expect(find.textContaining('Farms beyond this point'), findsNothing);
      expect(find.textContaining('km away'), findsNothing);

      // Higher confidence (Cabbage / Zulu Farm) first despite being nearer to
      // nothing and further alphabetically.
      expect(
        orderingOf(tester, 'Zulu Farm'),
        lessThan(orderingOf(tester, 'Alpha Farm')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('cards run nearly edge to edge with a tight gap', (
      tester,
    ) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup],
        confidences: const [('Chayote', 0.8)],
        loadResults: (term) async => [
          _listing('L1', 'Chayote', 'Farm One', farmId: 'F1'),
          _listing('L2', 'Chayote', 'Farm Two', farmId: 'F2'),
        ],
        farms: [_pinKmNorth('F1', 1.0), _pinKmNorth('F2', 2.0)],
      );

      final first = tester.getRect(find.byType(SearchResultCard).at(0));
      final second = tester.getRect(find.byType(SearchResultCard).at(1));

      // Side margin is small so the photo is what fills the screen.
      expect(first.left, lessThan(8));
      expect(390 - second.right, lessThan(8));
      // Barely any seam between neighbours.
      expect(second.left - first.right, closeTo(4, 0.5));
      // Taller cell than text search: height/width is well above 1, so most of
      // the card is photo.
      expect(first.height / first.width, greaterThan(1.2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dead GPS does not leave the results on the loader', (
      tester,
    ) async {
      // Regression: when tryBuyerPosition() returns null the screen used to
      // await a second geolocator call as a "fallback". Under a wedged platform
      // channel that future never completes and the buyer stares at a spinner
      // forever. There is no longer any fallback callback to hand it a hanging
      // one, so the hang is now impossible by construction — this test pins the
      // behaviour that survives: results still load, with no distances.
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: SearchResultsScreen(
            query: 'Chayote',
            groups: const [chayoteGroup],
            loadResults: (term) async => [
              _listing('L1', 'Chayote', 'A Farm', farmId: 'F1'),
            ],
            loadFarms: () async => [_pinKmNorth('F1', 1.0)],
            loadBuyerPosition: () async => null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Rendered, not spinning.
      expect(find.byType(SearchResultCard), findsOneWidget);
      expect(find.text('A Farm'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('Turn on location to see the closest farms first.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('equal distances are broken by detection confidence', (
      tester,
    ) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup, cabbageGroup],
        confidences: const [('Chayote', 0.2), ('Cabbage', 0.99)],
        loadResults: (term) async => switch (term) {
          'chayote' => [
            _listing('L1', 'Chayote', 'Low Conf Farm', farmId: 'F1'),
          ],
          'sayote' => const [],
          'cabbage' => [
            _listing('L2', 'Cabbage', 'High Conf Farm', farmId: 'F2'),
          ],
          _ => const [],
        },
        // Both farms at the SAME point, so only confidence can order them.
        farms: [
          _pin('F1', _userPos.latitude, _userPos.longitude),
          _pin('F2', _userPos.latitude, _userPos.longitude),
        ],
      );

      expect(
        orderingOf(tester, 'High Conf Farm'),
        lessThan(orderingOf(tester, 'Low Conf Farm')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no results keeps an empty state, no divider', (tester) async {
      await pumpImageSearch(
        tester,
        groups: const [chayoteGroup],
        confidences: const [('Chayote', 0.5)],
        loadResults: (term) async => const [],
        farms: [_pinKmNorth('F1', 1.0)],
      );

      expect(find.text('No farms selling these crops yet.'), findsOneWidget);
      expect(find.textContaining('Farms beyond this point'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
