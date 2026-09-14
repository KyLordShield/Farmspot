import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:farmspot_app/services/routing_service.dart';

/// A realistic OSRM v5 response (mirrors what the real server returns): routes
/// wrap legs, each step carries maneuver.type/modifier + street name but no
/// server-side `instruction` string — the client must synthesize the text.
Map<String, dynamic> _osrmBody({
  double distance = 24685.4,
  double duration = 2259.2,
}) {
  return {
    'code': 'Ok',
    'routes': [
      {
        'legs': [
          {
            'distance': 24685.4,
            'duration': 2259.2,
            'summary': 'Ramon Duterte Street',
            'steps': [
              {
                'maneuver': {
                  'type': 'depart',
                  'bearing_after': 71,
                  'location': [123.88539, 10.315727],
                },
                'name': 'Ramon Duterte Street',
                'distance': 3.7,
                'duration': 2.4,
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [123.88539, 10.315727],
                    [123.885422, 10.315738],
                  ],
                },
              },
              {
                'maneuver': {
                  'type': 'turn',
                  'modifier': 'sharp left',
                  'location': [123.852204, 10.375488],
                },
                'name': 'Bonbon-Sudlon Road',
                'distance': 316.7,
                'duration': 28.5,
              },
              {
                'maneuver': {'type': 'arrive', 'location': [123.7847, 10.3796]},
                'name': '',
                'distance': 0.0,
                'duration': 0.0,
              },
            ],
          }
        ],
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [123.8854, 10.3157],
            [123.85, 10.37],
            [123.7847, 10.3796],
          ],
        },
        'distance': distance,
        'duration': duration,
      }
    ],
  };
}

void main() {
  group('getRoute', () {
    test('builds the routed-car URL (lon,lat order) and parses the route',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(_osrmBody()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = RoutingService(client: client);
      final plan = await service.getRoute(
        from: const LatLng(10.3157, 123.8854),
        to: const LatLng(10.3796, 123.7847),
        profile: 'car',
      );

      expect(captured.url.host, 'routing.openstreetmap.de');
      expect(captured.url.path,
          '/routed-car/route/v1/driving/123.8854,10.3157;123.7847,10.3796');
      expect(captured.url.queryParameters['overview'], 'full');
      expect(captured.url.queryParameters['geometries'], 'geojson');
      expect(captured.url.queryParameters['steps'], 'true');
      expect(captured.headers['User-Agent'],
          'FarmSpot/1.0 (student capstone project)');

      expect(plan, isNotNull);
      expect(plan!.distanceMeters, 24685.4);
      expect(plan.durationSeconds, 2259.2);
      expect(plan.geometry, hasLength(3),
          reason: 'GeoJSON [lon,lat] pairs must be parsed into LatLng points');
      expect(plan.geometry.first.latitude, closeTo(10.3157, 1e-9));
      expect(plan.geometry.first.longitude, closeTo(123.8854, 1e-9));
      expect(plan.geometry.last.longitude, closeTo(123.7847, 1e-9));
    });

    test('maps profile "foot" to routed-foot', () async {
      late http.Request captured;
      final service = RoutingService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(_osrmBody()), 200);
        }),
      );
      await service.getRoute(
        from: const LatLng(10.3157, 123.8854),
        to: const LatLng(10.3796, 123.7847),
        profile: 'foot',
      );
      expect(captured.url.path,
          '/routed-foot/route/v1/driving/123.8854,10.3157;123.7847,10.3796');
    });

    test('parses step distances and synthesizes readable instructions',
        () async {
      final service = RoutingService(
        client: MockClient(
            (_) async => http.Response(jsonEncode(_osrmBody()), 200)),
      );
      final plan = await service.getRoute(
        from: const LatLng(10.3157, 123.8854),
        to: const LatLng(10.3796, 123.7847),
        profile: 'car',
      );

      expect(plan!.steps, hasLength(3));
      expect(plan.steps.first.distanceMeters, 3.7);
      expect(plan.steps.first.instruction, 'Head out on Ramon Duterte Street');
      expect(plan.steps[1].instruction, 'Turn sharp left onto Bonbon-Sudlon Road');
      expect(plan.steps.last.instruction, 'Arrive at your destination');
    });

    test('prefers a server-provided instruction string when present', () async {
      final body = _osrmBody();
      (body['routes'] as List).first['instruction'] = 'IGNORED (route level)';
      ((body['routes'] as List).first['legs'] as List).first['steps'] = [
        {
          'instruction': 'Head north on Ramon Duterte Street',
          'maneuver': {'type': 'depart'},
          'name': 'Ramon Duterte Street',
          'distance': 3.7,
        },
      ];
      final service = RoutingService(
        client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
      );
      final plan = await service.getRoute(
        from: const LatLng(10.3157, 123.8854),
        to: const LatLng(10.3796, 123.7847),
        profile: 'car',
      );
      expect(plan!.steps.single.instruction,
          'Head north on Ramon Duterte Street');
    });

    test('returns null on non-200', () async {
      final service = RoutingService(
        client: MockClient((_) async => http.Response('{}', 429)),
      );
      final plan = await service.getRoute(
        from: const LatLng(10.3157, 123.8854),
        to: const LatLng(10.3796, 123.7847),
        profile: 'car',
      );
      expect(plan, isNull);
    });

    test('returns null when the body is malformed JSON', () async {
      final service = RoutingService(
        client: MockClient((_) async => http.Response('not json', 200)),
      );
      final plan = await service.getRoute(
        from: const LatLng(10.3157, 123.8854),
        to: const LatLng(10.3796, 123.7847),
        profile: 'car',
      );
      expect(plan, isNull);
    });

    test('returns null when the JSON lacks a route block', () async {
      final service = RoutingService(
        client: MockClient(
            (_) async => http.Response(jsonEncode({'code': 'NoRoute'}), 200)),
      );
      final plan = await service.getRoute(
        from: const LatLng(10.3157, 123.8854),
        to: const LatLng(10.3796, 123.7847),
        profile: 'car',
      );
      expect(plan, isNull);
    });

    test('returns null when the client throws (no internet)', () async {
      final service = RoutingService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final plan = await service.getRoute(
        from: const LatLng(10.3157, 123.8854),
        to: const LatLng(10.3796, 123.7847),
        profile: 'car',
      );
      expect(plan, isNull);
    });

    test('spaces consecutive requests at least minInterval apart', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode(_osrmBody()), 200));
      final service =
          RoutingService(client: client, minInterval: const Duration(seconds: 1));
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 2; i++) {
        await service.getRoute(
          from: const LatLng(10.3157, 123.8854),
          to: const LatLng(10.3796, 123.7847),
          profile: 'car',
        );
      }
      stopwatch.stop();
      expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
    });
  });

  group('parseRouteResponse', () {
    test('returns null for a null routes list', () {
      expect(RoutingService.parseRouteResponse({}), isNull);
      expect(
        RoutingService.parseRouteResponse({
          'routes': <Object>[],
        }),
        isNull,
      );
    });

    test('returns null when route totals are missing', () {
      expect(
        RoutingService.parseRouteResponse({
          'routes': [
            {'legs': []},
          ],
        }),
        isNull,
      );
    });
  });
}