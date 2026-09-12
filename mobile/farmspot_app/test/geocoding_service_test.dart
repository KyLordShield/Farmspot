import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:farmspot_app/services/geocoding_service.dart';

void main() {
  group('reverseGeocode', () {
    test('sends a proper User-Agent, lat/lon and parses a short address',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'display_name':
                'Sitio Maraag, Barangay Sudlon II, Cebu City, Central Visayas, 6000, Philippines',
            'address': {
              'neighbourhood': 'Sitio Maraag',
              'suburb': 'Barangay Sudlon II',
              'city': 'Cebu City',
              'state': 'Central Visayas',
              'postcode': '6000',
              'country': 'Philippines',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = GeocodingService(client: client);
      final address = await service.reverseGeocode(
        const LatLng(10.3178, 123.8742),
      );

      expect(captured.url.host, 'nominatim.openstreetmap.org');
      expect(captured.url.path, '/reverse');
      expect(captured.url.queryParameters['format'], 'json');
      expect(captured.url.queryParameters['lat'], '10.3178');
      expect(captured.url.queryParameters['lon'], '123.8742');
      expect(captured.url.queryParameters['addressdetails'], '1');
      expect(captured.headers['User-Agent'],
          'FarmSpot/1.0 (student capstone project)');
      expect(address, 'Sitio Maraag, Barangay Sudlon II, Cebu City');
    });

    test('returns null on non-200 (rate limit / server error)', () async {
      final service = GeocodingService(
        client: MockClient((_) async => http.Response('{}', 429)),
      );
      expect(
        await service.reverseGeocode(const LatLng(10.3178, 123.8742)),
        isNull,
      );
    });

    test('returns null when the response is malformed', () async {
      final service = GeocodingService(
        client: MockClient((_) async => http.Response('not json', 200)),
      );
      expect(
        await service.reverseGeocode(const LatLng(10.3178, 123.8742)),
        isNull,
      );
    });

    test('returns null when the client throws (no internet)', () async {
      final service = GeocodingService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(
        await service.reverseGeocode(const LatLng(10.3178, 123.8742)),
        isNull,
      );
    });
  });

  group('search', () {
    test('restricts to the Philippines and parses results', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode([
            {
              'display_name': 'Barangay Busay, Cebu City, Philippines',
              'lat': '10.3506',
              'lon': '123.8842',
            },
            {
              'display_name': 'Busay, Barangay, Cebu, Philippines',
              'lat': '10.3100',
              'lon': '123.8900',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = GeocodingService(client: client);
      final results = await service.search('busay');

      expect(captured.url.path, '/search');
      expect(captured.url.queryParameters['q'], 'busay');
      expect(captured.url.queryParameters['countrycodes'], 'ph');
      expect(captured.url.queryParameters['limit'], '5');
      expect(captured.url.queryParameters['viewbox'], '123.75,10.17,123.98,10.50');
      expect(captured.url.queryParameters['bounded'], '1');
      expect(captured.headers['User-Agent'],
          'FarmSpot/1.0 (student capstone project)');
      expect(results, hasLength(2));
      expect(results.first.displayName, 'Barangay Busay, Cebu City, Philippines');
      expect(results.first.latitude, 10.3506);
      expect(results.first.longitude, 123.8842);
    });

    test('defaults to the hard-bound Cebu pilot box', () async {
      late http.Request captured;
      final service = GeocodingService(
        client: MockClient((request) async {
          captured = request;
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await service.search('sudlon');
      expect(captured.url.queryParameters['viewbox'],
          GeocodingService.cebuPilotViewbox);
      expect(captured.url.queryParameters['bounded'], '1');
      expect(captured.url.queryParameters['countrycodes'], 'ph');
    });

    test('accepts a wider viewbox and soft preference explicitly', () async {
      late http.Request captured;
      final service = GeocodingService(
        client: MockClient((request) async {
          captured = request;
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await service.search(
        'bohol',
        viewbox: '123.00,9.50,125.50,11.50', // whole Central Visayas
        bounded: false,
      );
      expect(captured.url.queryParameters['viewbox'],
          '123.00,9.50,125.50,11.50');
      expect(captured.url.queryParameters['bounded'], '0');
    });

    test('returns an empty list on failure instead of throwing', () async {
      final service = GeocodingService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await service.search('busay'), isEmpty);
    });

    test('returns an empty list for a blank query and never hits the network',
        () async {
      var called = false;
      final service = GeocodingService(
        client: MockClient((_) async {
          called = true;
          return http.Response('[]', 200);
        }),
      );
      expect(await service.search('   '), isEmpty);
      expect(called, isFalse);
    });
  });

  group('shortName', () {
    test('truncates long display names for the pick list', () {
      const place = GeocodePlace(
        displayName:
            'Barangay Sudlon II, Cebu City, Central Visayas, 6000, Philippines',
        latitude: 10.0,
        longitude: 123.0,
      );
      expect(place.shortName, 'Barangay Sudlon II, Cebu City, Central Visayas, …');
    });
  });

  group('parseReverseResponse', () {
    test('drops the postcode from the display_name fallback', () {
      final result = GeocodingService.parseReverseResponse({
        'display_name': 'Somewhere, Cebu City, 6000, Philippines',
      });
      expect(result, 'Somewhere, Cebu City, Philippines');
    });
  });
}