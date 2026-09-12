import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/farm_setup_data.dart';
import 'package:farmspot_app/screens/seller/farm_setup_location_screen.dart';
import 'package:farmspot_app/services/geocoding_service.dart';

/// A fake geolocator used to keep the widget tests deterministic. In a widget
/// test there is no Android/iOS host, so `GeolocatorPlatform.instance` is
/// replaced here; every call throws `MissingPluginException`, which is exactly
/// what the real method channel does on a device without the plugin, and the
/// screen must swallow it and fall back to the default Sitio Maraag area.
class _FakeGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async =>
      throw MissingPluginException();

  @override
  Future<LocationPermission> checkPermission() async =>
      throw MissingPluginException();

  @override
  Future<LocationPermission> requestPermission() async =>
      throw MissingPluginException();

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async =>
      throw MissingPluginException();
}

/// A fake Nominatim client so the widget tests never touch the network.
class _FakeGeocodingService implements GeocodingService {
  _FakeGeocodingService({this.address, this.searchResults = const []});

  /// Address returned by reverseGeocode; when null the real service would
  /// have failed, exercising the raw-coordinates fallback.
  final String? address;
  final List<GeocodePlace> searchResults;

  int reverseCalls = 0;
  final List<String> searchQueries = [];

  @override
  Future<String?> reverseGeocode(LatLng point) async {
    reverseCalls++;
    return address;
  }

  @override
  Future<List<GeocodePlace>> search(
    String query, {
    int limit = 5,
    String viewbox = GeocodingService.cebuPilotViewbox,
    bool bounded = true,
  }) async {
    searchQueries.add(query);
    return searchResults;
  }

  @override
  Future<void> close() async {}

  @override
  Duration get minInterval => const Duration(seconds: 1);
}

// pumpAndSettle is avoided here: the map's tile layer and any transient
// spinner keep scheduling frames, so the tests rely on fixed-duration pumps.

Future<_FakeGeocodingService> _pumpScreen(
  WidgetTester tester,
  FarmSetupData data, {
  String? address,
  List<GeocodePlace> searchResults = const [],
}) async {
  final fakeGeo = _FakeGeocodingService(
    address: address,
    searchResults: searchResults,
  );
  final original = GeolocatorPlatform.instance;
  GeolocatorPlatform.instance = _FakeGeolocator();
  addTearDown(() => GeolocatorPlatform.instance = original);

  await tester.pumpWidget(
    MaterialApp(
      home: FarmSetupLocationScreen(
        farmSetupData: data,
        geocodingService: fakeGeo,
      ),
    ),
  );
  // Let the geolocator failure surface and the default state build.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 200));
  return fakeGeo;
}

/// The selected-coordinates text inside the info card under the map
/// (e.g. "10.317800, 123.874200").
String? _coordinateText(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final d = text.data ?? '';
    if (d.contains(',') && d.contains('1')) return d;
  }
  return null;
}

void main() {
  testWidgets('GPS unavailable: falls back to a default area, no crash',
      (tester) async {
    await _pumpScreen(tester, FarmSetupData());

    expect(tester.takeException(), isNull,
        reason: 'geolocator MissingPluginException must be swallowed');
    expect(find.byType(FlutterMap), findsOneWidget,
        reason: 'the real map must render even without GPS');
    expect(find.textContaining('GPS'), findsOneWidget,
        reason: 'must tell the farmer GPS was not available');
    expect(_coordinateText(tester), contains('10.317800'),
        reason: 'must show the default fallback coordinates');
  });

  testWidgets('tapping the map moves the pin and updates the coordinates',
      (tester) async {
    await _pumpScreen(tester, FarmSetupData());

    final mapRect = tester.getRect(find.byType(FlutterMap));
    const offset = Offset(40, 20);
    await tester.tapAt(mapRect.center + offset);
    // flutter_map defers onTap by its double-tap delay (250 ms), and the
    // reverse-geocode debounce is 700 ms, so pump past both.
    await tester.pump(const Duration(milliseconds: 850));

    expect(tester.takeException(), isNull);
    expect(
      _coordinateText(tester),
      isNot(contains('10.317800')),
      reason: 'the pin must have moved off the default area',
    );
  });

  testWidgets('confirm writes the real selected lat/lng into FarmSetupData',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final data = FarmSetupData()..name = 'Test Farm';

    await _pumpScreen(tester, data);

    final mapRect = tester.getRect(find.byType(FlutterMap));
    const offset = Offset(-40, 30);
    await tester.tapAt(mapRect.center + offset);
    await tester.pump(const Duration(milliseconds: 850));

    // Confirming stores the tapped coordinates on the shared wizard model,
    // then attempts the network call, which fails without a token — we only
    // verify the data wiring here.
    await tester.tap(find.text('Create My Farm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));

    expect(data.latitude, isNotNull,
        reason: 'farmSetupData.latitude must be set on confirm');
    expect(data.longitude, isNotNull,
        reason: 'farmSetupData.longitude must be set on confirm');
    expect(data.latitude, isNot(closeTo(10.3178, 0.0001)),
        reason: 'the stored lat/lng must be the tapped point, not the fallback');
  });

  testWidgets('dragging the marker updates the selected coordinates',
      (tester) async {
    await _pumpScreen(tester, FarmSetupData());

    final markerFinder = find.byIcon(Icons.location_pin);
    expect(markerFinder, findsOneWidget);
    final start = tester.getCenter(markerFinder);

    // An explicit, incremental gesture so the marker's pan recognizer cleanly
    // wins the gesture arena against the map's own drag recognizer. The pan
    // is accepted on the second move; a third move guarantees an onPanUpdate
    // (flutter does not emit an update for the move that accepts the gesture).
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-12, -9));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-28, -21));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-10, -10));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 850));

    expect(tester.takeException(), isNull,
        reason: 'dragging the pin must not throw');
    expect(
      _coordinateText(tester),
      isNot(contains('10.317800')),
      reason: 'the pin must have moved off the default area after dragging',
    );
  });

  testWidgets('readable address shows after the pin settles, not mid-drag',
      (tester) async {
    final fakeGeo = await _pumpScreen(
      tester,
      FarmSetupData(),
      address: 'Sitio Maraag, Barangay Sudlon II, Cebu City',
    );

    expect(fakeGeo.reverseCalls, 0,
        reason: 'no reverse lookup before any pin interaction');

    final markerFinder = find.byIcon(Icons.location_pin);
    final start = tester.getCenter(markerFinder);

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-12, -9));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(-28, -21));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(-10, -10));
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakeGeo.reverseCalls, 0,
        reason: 'must NOT reverse-geocode while the pin is still being dragged');
    expect(find.textContaining('Looking up the area'), findsNothing,
        reason: 'no loading state should appear mid-drag');

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(fakeGeo.reverseCalls, 0,
        reason: 'the debounce is 700 ms after the drag ends');
    expect(
      find.textContaining('Sitio Maraag, Barangay Sudlon II, Cebu City'),
      findsNothing,
      reason: 'address must not appear before the debounce elapses',
    );

    await tester.pump(const Duration(milliseconds: 700));
    expect(fakeGeo.reverseCalls, 1,
        reason: 'exactly one lookup after the pin settles');
    expect(
      find.textContaining('Sitio Maraag, Barangay Sudlon II, Cebu City'),
      findsOneWidget,
      reason: 'a readable address must replace the raw coordinates once settled',
    );
  });

  testWidgets('failed reverse lookup falls back to raw coordinates',
      (tester) async {
    // address: null -> the real service failed (offline/rate-limited/error).
    await _pumpScreen(tester, FarmSetupData());

    final mapRect = tester.getRect(find.byType(FlutterMap));
    await tester.tapAt(mapRect.center + const Offset(30, 20));
    await tester.pump(const Duration(milliseconds: 850));

    expect(tester.takeException(), isNull,
        reason: 'a failed reverse lookup must never break the screen');
    expect(_coordinateText(tester), isNot(contains('10.317800')),
        reason: 'the pin moved, and the card falls back to raw coordinates');
  });

  testWidgets('search with no results shows a clear message',
      (tester) async {
    await _pumpScreen(tester, FarmSetupData());

    await tester.enterText(
        find.byType(TextField), 'no such barangay anywhere');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('No results for'), findsOneWidget,
        reason: 'must explain there were no matches, not stay silent');
  });

  testWidgets('search with one result jumps the map and places the pin',
      (tester) async {
    await _pumpScreen(
      tester,
      FarmSetupData(),
      searchResults: const [
        GeocodePlace(
          displayName: 'Barangay Busay, Cebu City, Philippines',
          latitude: 10.3506,
          longitude: 123.8842,
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'Busay');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(const Duration(milliseconds: 850));

    expect(tester.takeException(), isNull);
    expect(_coordinateText(tester), isNot(contains('10.317800')),
        reason: 'a single match must move the pin to that place on its own');
  });

  testWidgets('search with several matches lists them and lets the farmer pick',
      (tester) async {
    final fakeGeo = await _pumpScreen(
      tester,
      FarmSetupData(),
      searchResults: const [
        GeocodePlace(
          displayName: 'Lahug, Cebu City, Philippines',
          latitude: 10.3200,
          longitude: 123.8750,
        ),
        GeocodePlace(
          displayName: 'Guadalupe, Cebu City, Philippines',
          latitude: 10.3150,
          longitude: 123.8740,
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'Cebu');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fakeGeo.searchQueries, ['Cebu']);
    expect(find.textContaining('Lahug, Cebu City'), findsOneWidget,
        reason: 'multiple matches must be shown as a pick list');
    expect(find.textContaining('Guadalupe, Cebu City'), findsOneWidget);

    await tester.tap(find.textContaining('Lahug, Cebu City'));
    await tester.pump(const Duration(milliseconds: 850));

    expect(tester.takeException(), isNull);
    expect(_coordinateText(tester), contains('10.320000'),
        reason: 'picking Lahug places the pin on its coordinates');
  });
}