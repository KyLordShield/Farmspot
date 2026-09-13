import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/farm_pin.dart';
import 'package:farmspot_app/screens/farm_profile_screen.dart';
import 'package:farmspot_app/screens/map_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

const _userPos = LatLng(10.3178, 123.8742);

FarmPin _pin(
  String id,
  String name,
  double lat,
  double lon, {
  int count = 3,
  String? barangay = 'Sudlon II',
}) {
  return FarmPin(
    id: id,
    name: name,
    barangay: barangay,
    latitude: lat,
    longitude: lon,
    activeListingsCount: count,
    photoUrl: null,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  List<FarmPin> farms = const [],
  Future<LatLng> Function()? position,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      home: MapScreen(
        loadFarms: () async => farms,
        loadPosition: position ?? () async => _userPos,
      ),
    ),
  );
  // Let the async loaders resolve and the map build. Fixed pumps only —
  // pumpAndSettle never settles with (a) tile images or (b) FarmProfile's
  // transient spinner, so never use it here.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('renders a real OSM map with farm pins at real coordinates',
      (tester) async {
    await _pump(tester, farms: [
      _pin('F1', 'Sitio Maraag Farm', 10.3178, 123.8742, count: 3),
      _pin('F2', 'Agus Farm', 10.3172, 123.8742, count: 1),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget,
        reason: 'the placeholder map must be gone; a real OSM map renders');
    expect(find.byType(TileLayer), findsOneWidget,
        reason: 'the OSM tile layer (same setup as the wizard) must be present');
    expect(find.byIcon(Icons.location_on), findsNWidgets(2),
        reason: 'two farm pins must plot, one per farm');
    expect(find.byIcon(Icons.navigation), findsOneWidget,
        reason: 'the distinct blue buyer-position marker must render');
    expect(find.text('Sitio Maraag Farm'), findsNothing,
        reason: 'no card until a pin is tapped');
  });

  testWidgets('tapping a farm pin shows real farm data, not the mockup',
      (tester) async {
    await _pump(tester, farms: [
      _pin('F1', 'Sitio Maraag Farm', 10.3178, 123.8742, count: 3),
      _pin('F2', 'Lahug Farm', 10.3200, 123.8830, count: 1),
    ]);

    await tester.tap(find.byIcon(Icons.location_on).first);
    await tester.pump();

    expect(find.text('Sitio Maraag Farm'), findsOneWidget,
        reason: 'the card must show the tapped farm real name');
    expect(find.text('3 crops available'), findsOneWidget,
        reason: 'the real active-listing count must show');
    expect(find.textContaining('Sudlon II'), findsWidgets,
        reason: 'the farm barangay must show');

    final distanceText = tester
        .widgetList<Text>(find.textContaining('away'))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    expect(distanceText, isNotEmpty,
        reason: 'a real distance from the buyer must be shown');

    // The entire fake mockup must be gone — no hardcoded farm, no fake crops.
    expect(find.text('Mr. A Farm'), findsNothing);
    expect(find.textContaining('Crop name:'), findsNothing);
    expect(find.textContaining('P_status'), findsNothing);
  });

  testWidgets('tapping the map clears the selected farm card', (tester) async {
    await _pump(tester, farms: [
      _pin('F1', 'Sitio Maraag Farm', 10.3178, 123.8742),
    ]);

    await tester.tap(find.byIcon(Icons.location_on).first);
    await tester.pump();
    expect(find.text('Sitio Maraag Farm'), findsOneWidget);

    // Tap an empty corner of the map far from the pin.
    final mapRect = tester.getRect(find.byType(FlutterMap));
    await tester.tapAt(mapRect.topLeft + const Offset(12, 12));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Sitio Maraag Farm'), findsNothing,
        reason: 'tapping open map space must dismiss the card');
  });

  testWidgets('Listing toggle shows a real scrollable list of farms',
      (tester) async {
    await _pump(tester, farms: [
      _pin('F1', 'Sitio Maraag Farm', 10.3178, 123.8742, count: 2),
      _pin('F2', 'Agus Farm', 10.3200, 123.9000, count: 0),
    ]);

    await tester.tap(find.text('Listing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ListView), findsOneWidget,
        reason: 'the Listing option must render a scrollable list');
    expect(find.text('Sitio Maraag Farm'), findsOneWidget);
    expect(find.text('Agus Farm'), findsOneWidget);
    expect(find.text('2 crops available'), findsOneWidget,
        reason: 'list rows show the real active-listing count');
    expect(find.text('0 crops available'), findsOneWidget);
    expect(find.textContaining('km away'), findsWidgets,
        reason: 'list rows show the real distance from the buyer');

    await tester.tap(find.text('Agus Farm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FarmProfileScreen), findsOneWidget,
        reason: 'tapping a list row must open that farm profile');
    expect(tester.widget<FarmProfileScreen>(find.byType(FarmProfileScreen)).farmId,
        'F2');
  });

  testWidgets('tap on the bottom card farm name opens the real Farm Profile',
      (tester) async {
    await _pump(tester, farms: [
      _pin('F1', 'Sitio Maraag Farm', 10.3178, 123.8742, count: 3),
    ]);

    await tester.tap(find.byIcon(Icons.location_on).first);
    await tester.pump();

    await tester.tap(find.text('Sitio Maraag Farm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FarmProfileScreen), findsOneWidget,
        reason: 'the farm name on the bottom card must open the real profile '
            '(same affordance as ProductDetailScreen)');
    expect(
        tester
            .widget<FarmProfileScreen>(find.byType(FarmProfileScreen))
            .farmId,
        'F1');
  });

  testWidgets('tap on the bottom card photo thumbnail opens the real Farm Profile',
      (tester) async {
    await _pump(tester, farms: [
      _pin('F1', 'Sitio Maraag Farm', 10.3178, 123.8742, count: 3),
    ]);

    await tester.tap(find.byIcon(Icons.location_on).first);
    await tester.pump();

    // No photoUrl -> the crop placeholder thumbnail renders; it must be
    // tappable the same way the real network photo is.
    await tester.tap(find.byType(CropImagePlaceholder));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FarmProfileScreen), findsOneWidget,
        reason: 'the photo thumbnail on the bottom card must open the profile');
    expect(
        tester
            .widget<FarmProfileScreen>(find.byType(FarmProfileScreen))
            .farmId,
        'F1');
  });

  testWidgets('Directions shows the coming-soon notice, never the profile',
      (tester) async {
    await _pump(tester, farms: [
      _pin('F1', 'Sitio Maraag Farm', 10.3178, 123.8742, count: 3),
    ]);

    await tester.tap(find.byIcon(Icons.location_on).first);
    await tester.pump();

    await tester.tap(find.text('Directions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Turn-by-turn directions coming soon'), findsOneWidget,
        reason: 'Directions is not built yet; it must surface a clear notice');
    expect(find.byType(FarmProfileScreen), findsNothing,
        reason: 'Directions must NO LONGER open the Farm Profile screen');
  });

  testWidgets('default loaders fall back gracefully when GPS and farms fail',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _FakeGeolocator();
    addTearDown(() => GeolocatorPlatform.instance = original);

    // Default loadFarms hits the real endpoint (unreachable in a widget test
    // -> empty), default loadPosition hits geolocator (missing plugin ->
    // fallback center). Both must degrade without crashing.
    await tester.pumpWidget(const MaterialApp(home: MapScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: 'GPS + network failures must never crash the map screen');
    expect(find.byType(FlutterMap), findsOneWidget,
        reason: 'the real map must still render');
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.byIcon(Icons.navigation), findsOneWidget,
        reason: 'the fallback Cebu City buyer marker must show');

    // Empty feed -> listing view degrades to a friendly empty message.
    await tester.tap(find.text('Listing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No farms available right now.'), findsOneWidget);
  });

  testWidgets('farm pins survive a toggle back from Listing to Map',
      (tester) async {
    await _pump(tester, farms: [
      _pin('F1', 'Sitio Maraag Farm', 10.3178, 123.8742),
    ]);

    await tester.tap(find.text('Listing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FlutterMap), findsNothing);

    // The header toggle and the bottom nav both label the map "Map" — pick
    // the header one (first in the widget tree).
    await tester.tap(find.text('Map').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget,
        reason: 'the pin must plot again after switching back to Map');
  });
}

/// A fake geolocator raising MissingPluginException on every call — the exact
/// absence-of-plugin behavior a widget test environment exhibits.
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