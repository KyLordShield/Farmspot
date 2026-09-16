import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/screens/farm_directions_screen.dart';
import 'package:farmspot_app/services/routing_service.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

const _start = LatLng(10.3178, 123.8742);
const _mid = LatLng(10.3200, 123.8800);
const _farm = LatLng(10.3360, 123.8920);

late final Distance _distance;
late final double _leg1;
late final double _leg2;
late final double _footTotal;

String _fmtDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  if (km >= 10) return '${km.round()} km';
  return '${km.toStringAsFixed(1)} km';
}

/// Minimal OSRM v5 body. The geometry drives the journey math while the totals
/// stay small, fixed numbers (foot: 2400 m / 2000 s, car: 2100 m / 1020 s) so
/// the two pills always read "33 min" vs "17 min".
String _osrmBody({required bool foot, bool ferry = false}) {
  return jsonEncode({
    'code': 'Ok',
    'routes': [
      {
        'distance': foot ? 2400.0 : 2100.0,
        'duration': foot ? 2000.0 : 1020.0,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [_start.longitude, _start.latitude],
            [_mid.longitude, _mid.latitude],
            [_farm.longitude, _farm.latitude],
          ],
        },
        'legs': [
          {
            'steps': [
              {
                'distance': 0,
                'name': '',
                'maneuver': {
                  'type': 'depart',
                  'modifier': 'depart',
                  'location': [_start.longitude, _start.latitude],
                },
              },
              {
                'distance': _leg1,
                'name': 'Sudlon Road',
                'maneuver': {
                  'type': 'turn',
                  'modifier': 'left',
                  'location': [_mid.longitude, _mid.latitude],
                },
              },
              if (ferry)
                {
                  'distance': 4882.4,
                  'name': 'Cebu City to Lapu-Lapu City (Opon)',
                  'mode': 'ferry',
                  'maneuver': {
                    'type': 'notification',
                    'modifier': 'uturn',
                    'location': [_farm.longitude, _farm.latitude],
                  },
                },
              {
                'distance': _leg2,
                'name': 'Sitio Maraag',
                'maneuver': {
                  'type': 'arrive',
                  'modifier': 'arrive',
                  'location': [_farm.longitude, _farm.latitude],
                },
              },
            ],
          },
        ],
      },
    ],
  });
}

RoutingService _routing({bool fail = false, bool ferry = false}) {
  return RoutingService(
    client: MockClient((request) async {
      if (fail) return http.Response('oops', 500);
      final path = request.url.path;
      if (path.contains('routed-foot')) {
        return http.Response(_osrmBody(foot: true, ferry: ferry), 200);
      }
      if (path.contains('routed-car')) {
        return http.Response(_osrmBody(foot: false), 200);
      }
      return http.Response('not found', 404);
    }),
    minInterval: Duration.zero,
  );
}

FarmProfileData _profile({List<CropListing> listings = const []}) {
  return FarmProfileData(
    id: 'F1',
    name: 'Sitio Maraag Farm',
    barangay: 'Brgy. Sudlon',
    latitude: _farm.latitude,
    longitude: _farm.longitude,
    listings: listings,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required StreamController<LatLng> stream,
  RoutingService? routing,
  Future<FarmProfileData> Function(String)? loadFarmProfile,
  Future<Listing> Function(String)? loadListing,
  Future<void> Function({required String listingId, required String method})?
  contactLogger,
  Future<void> Function({required String number, required String method})?
  contactAction,
  String? listingId,
  LatLng? farmPosition,
  bool passFarmPosition = true,
  Future<LatLng> Function()? loadPosition,
  bool ferry = false,
  bool simulate = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FarmDirectionsScreen(
        farmId: 'F1',
        farmName: 'Sitio Maraag Farm',
        farmPosition: passFarmPosition ? (farmPosition ?? _farm) : null,
        listingId: listingId,
        loadPosition: loadPosition ?? () async => _start,
        loadFarmProfile: loadFarmProfile ?? (_) async => _profile(),
        loadListing: loadListing ?? (_) async => throw Exception('unused'),
        positionStream: () => stream.stream,
        routing: routing ?? _routing(ferry: ferry),
        contactLogger: contactLogger,
        contactAction: contactAction,
        simulate: simulate,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() {
    _distance = const Distance();
    _leg1 = _distance.as(LengthUnit.Meter, _start, _mid);
    _leg2 = _distance.as(LengthUnit.Meter, _mid, _farm);
    _footTotal = _leg1 + _leg2;
  });

  testWidgets('Step 1 shows the real farm with real walking + riding ETAs', (
    tester,
  ) async {
    final stream = StreamController<LatLng>();
    await _pump(tester, stream: stream);

    expect(tester.takeException(), isNull);
    expect(
      find.byType(FlutterMap),
      findsOneWidget,
      reason: 'the real map renders, not the mock CustomPaint',
    );
    expect(
      find.byType(PolylineLayer),
      findsWidgets,
      reason: 'the real route polyline must be drawn on the map',
    );
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.text('Sitio Maraag Farm'), findsOneWidget);
    expect(find.text('Brgy. Sudlon'), findsOneWidget);
    expect(
      find.text('33 min'),
      findsOneWidget,
      reason: 'real walking ETA from the routed-foot plan',
    );
    expect(
      find.text('17 min'),
      findsOneWidget,
      reason: 'real riding ETA from the routed-car plan',
    );
    expect(find.textContaining('walking'), findsOneWidget);
    expect(find.textContaining('riding'), findsOneWidget);
    expect(find.text('Start Navigation'), findsOneWidget);
  });

  testWidgets(
    'a ferry plan warns and offers the road/bridge riding route instead',
    (tester) async {
      final stream = StreamController<LatLng>();
      await _pump(tester, stream: stream, ferry: true);

      expect(
        find.text('Includes a ferry/boat crossing'),
        findsOneWidget,
        reason: 'the walking (foot) plan has a ferry leg, so Step 1 must warn',
      );
      expect(find.textContaining('boards a boat'), findsOneWidget);
      expect(
        find.textContaining('Use the riding route'),
        findsOneWidget,
        reason: 'the car plan crosses by bridge, so offer it as the alternative',
      );

      await tester.tap(find.textContaining('Use the riding route'));
      await tester.pump();

      expect(
        find.textContaining('Includes a ferry'),
        findsNothing,
        reason: 'after switching to riding the selected plan has no ferry',
      );
      expect(find.text('17 min'), findsOneWidget,
          reason: 'riding ETA is still shown');
    },
  );

  testWidgets(
    'mode toggle selects riding and the journey shows the real mode',
    (tester) async {
      final stream = StreamController<LatLng>();
      await _pump(tester, stream: stream);

      await tester.tap(find.text('17 min'));
      await tester.pump();
      await tester.tap(find.text('Start Navigation'));
      await tester.pump();

      expect(
        find.text('Riding'),
        findsOneWidget,
        reason: 'journey must honor the selected riding mode',
      );
      expect(find.text('Mark as Arrived'), findsOneWidget);
      expect(find.text('Cancel Navigation'), findsOneWidget);
    },
  );

  testWidgets(
    'journey shows real remaining ETA/distance and advances through turns',
    (tester) async {
      final stream = StreamController<LatLng>();
      await _pump(tester, stream: stream);

      await tester.tap(find.text('Start Navigation'));
      await tester.pump();

      expect(
        find.text('Walking'),
        findsOneWidget,
        reason: 'foot is the default mode',
      );
      expect(
        find.text(_fmtDistance(_footTotal)),
        findsOneWidget,
        reason: 'remaining distance = full walking route from the start',
      );
      expect(
        find.text('Turn left onto Sudlon Road'),
        findsOneWidget,
        reason: 'the first real maneuver shows as the current instruction',
      );
      expect(
        find.textContaining('Turn in'),
        findsOneWidget,
        reason: 'the banner says how far the turn is',
      );

      // Simulate reaching the turn point on the route.
      stream.add(_mid);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('Turn left onto Sudlon Road'),
        findsNothing,
        reason: 'the turn instruction must advance once the turn is passed',
      );
      expect(
        find.text('Arrive at Sitio Maraag'),
        findsOneWidget,
        reason: 'the next maneuver becomes the arrival instruction',
      );
      expect(
        find.text(_fmtDistance(_leg2)),
        findsOneWidget,
        reason: 'remaining distance shrinks to the last leg',
      );
      expect(
        find.textContaining('ahead'),
        findsOneWidget,
        reason: 'the arrival banner reports the farm is close',
      );
    },
  );

  testWidgets(
    'simulate glides the route without GPS and advances the turn banner',
    (tester) async {
      final stream = StreamController<LatLng>();
      await _pump(tester, stream: stream, simulate: true);

      expect(find.text('Start Navigation'), findsOneWidget);
      await tester.tap(find.text('Start Navigation'));
      await tester.pump();

      expect(
        find.textContaining('SIMULATED DEMO'),
        findsOneWidget,
        reason: 'the journey must state it is replaying fake positions',
      );
      expect(find.text(_fmtDistance(_footTotal)), findsOneWidget,
          reason: 'remaining distance starts at the full walking route');
      expect(
        find.text('Turn left onto Sudlon Road'),
        findsOneWidget,
        reason: 'the first real maneuver shows as the current instruction',
      );
      expect(find.textContaining('Turn in'), findsOneWidget,
          reason: 'the banner says how far the turn is');

      // ~150 interpolated 8m hops (~12s fake time) reaches past the mid turn
      // point (~700m into the ~2800m path), which must advance the banner.
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 84));
      }
      expect(
        find.text('Arrive at Sitio Maraag'),
        findsOneWidget,
        reason: 'the turn instruction must advance once crossed (was stuck '
            'before, because the old simulation jumped over it)',
      );

      // Finish the ~25s replay; the marker parks on the farm.
      for (var i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 84));
      }
      expect(
        find.text('0 m'),
        findsWidgets,
        reason: 'after the replay the remaining distance reaches the farm',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'arriving from a listing shows the real crop, farmer and contact',
    (tester) async {
      final stream = StreamController<LatLng>();
      final listing = Listing(
        id: 'L9',
        cropIcon: 'Cabbage',
        status: 'AVAILABLE_NOW',
        farmerName: 'Juan Dela Cruz',
        farmerMobileNumber: '0917-000-0000',
        categoryName: 'Vegetable',
      );
      await _pump(
        tester,
        stream: stream,
        listingId: 'L9',
        loadListing: (_) async => listing,
      );

      await tester.tap(find.text('Start Navigation'));
      await tester.pump();
      await tester.tap(find.text('Mark as Arrived'));
      await tester.pump();

      expect(find.text("You've Arrived!"), findsOneWidget);
      expect(
        find.text('Cabbage'),
        findsOneWidget,
        reason: 'the real crop name replaces the hardcoded one',
      );
      expect(find.text('Available Now'), findsOneWidget);
      expect(
        find.text('Juan Dela Cruz'),
        findsOneWidget,
        reason: 'the real farmer name shows, not "Little A"',
      );
      expect(
        find.text('0917-000-0000'),
        findsOneWidget,
        reason: 'the real contact number shows, not the fake one',
      );
      expect(find.text('Back to Browse'), findsOneWidget);
    },
  );

  testWidgets('call and SMS log contact against the real listing', (
    tester,
  ) async {
    final stream = StreamController<LatLng>();
    final logs = <String>[];
    final actions = <String>[];
    final listing = Listing(
      id: 'L9',
      cropIcon: 'Cabbage',
      status: 'AVAILABLE_NOW',
      farmerName: 'Juan Dela Cruz',
      farmerMobileNumber: '0917-000-0000',
      categoryName: 'Vegetable',
    );
    await _pump(
      tester,
      stream: stream,
      listingId: 'L9',
      loadListing: (_) async => listing,
      contactLogger:
          ({required String listingId, required String method}) async {
            logs.add('$listingId:$method');
          },
      contactAction: ({required String number, required String method}) async {
        actions.add('$number:$method');
      },
    );

    await tester.tap(find.text('Start Navigation'));
    await tester.pump();
    await tester.tap(find.text('Mark as Arrived'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.phone));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();

    expect(logs, [
      'L9:CALL',
      'L9:SMS',
    ], reason: 'both actions must be logged against the real listing');
    expect(actions, [
      '0917-000-0000:CALL',
      '0917-000-0000:SMS',
    ], reason: 'the real phone number is passed to the launcher');
  });

  testWidgets('GPS failure falls back to the default area without crashing', (
    tester,
  ) async {
    final stream = StreamController<LatLng>();
    await _pump(
      tester,
      stream: stream,
      loadPosition: () async => throw Exception('permission denied'),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'GPS denial must never crash the directions flow',
    );
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      find.text('Start Navigation'),
      findsOneWidget,
      reason: 'routing still works from the fallback position',
    );
  });

  testWidgets('no internet (both routers fail) shows a friendly error', (
    tester,
  ) async {
    final stream = StreamController<LatLng>();
    await _pump(tester, stream: stream, routing: _routing(fail: true));

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Could not calculate a route'),
      findsOneWidget,
      reason: 'route failure must surface a clear message, not crash',
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('farm without a pinned location degrades gracefully', (
    tester,
  ) async {
    final stream = StreamController<LatLng>();
    await _pump(
      tester,
      stream: stream,
      passFarmPosition: false,
      loadFarmProfile: (_) async => FarmProfileData(
        id: 'F1',
        name: 'Sitio Maraag Farm',
        latitude: null,
        longitude: null,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('no location set yet'), findsOneWidget);
  });

  testWidgets(
    'profile fetch failure still navigates via the map coords; no contact shown',
    (tester) async {
      final stream = StreamController<LatLng>();
      await _pump(
        tester,
        stream: stream,
        loadFarmProfile: (_) async => throw Exception('offline'),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('Sitio Maraag Farm'),
        findsOneWidget,
        reason: 'the name passed by the map screen still shows',
      );

      await tester.tap(find.text('Start Navigation'));
      await tester.pump();
      await tester.tap(find.text('Mark as Arrived'));
      await tester.pump();

      expect(
        find.text('No contact number is linked to this farm yet.'),
        findsOneWidget,
        reason: 'without listing/profile data there is no contact to fake',
      );
    },
  );
}
