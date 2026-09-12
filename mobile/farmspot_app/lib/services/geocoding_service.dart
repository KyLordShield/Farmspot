import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A single forward-geocoding result from Nominatim (a place the farmer
/// searched for).
class GeocodePlace {
  const GeocodePlace({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final String displayName;
  final double latitude;
  final double longitude;

  /// A shorter, friendlier label for result rows — Nominatim display names are
  /// the full "area, barangay, city, region, postcode, country" chain.
  String get shortName {
    final parts = displayName.split(', ');
    if (parts.length <= 3) return displayName;
    return '${parts.sublist(0, 3).join(', ')}, …';
  }
}

/// Thin client over Nominatim (the free OpenStreetMap geocoder, no API key).
///
/// Nominatim's usage policy requires at most 1 request/second and a valid
/// User-Agent identifying the app, so every request here carries a descriptive
/// `User-Agent` header and consecutive requests are spaced at least
/// `minInterval` apart. The callers (the location screen) additionally debounce
/// reverse-geocoding so a settled pin never floods the service.
///
/// Every method is failure-tolerant: network errors, timeouts, throttling and
/// malformed responses all degrade to `null` / an empty list so the wizard is
/// never blocked.
class GeocodingService {
  /// Geographic bounding box for the Cebu City pilot area used by
  /// [search] when no custom [viewbox] override is passed.
  ///
  /// The coordinates come from OpenStreetMap's official boundary for Cebu City
  /// (relation 12455830, S 10.2463 / N 10.4963 / W 123.7596 / E 123.9302)
  /// extended with a thin margin for the immediate metro fringe
  /// (Talisay to the south, Mactan/Lapu-Lapu to the east) and a bit of
  /// headroom in the north so that all of the city's upland barangays —
  /// including the pilot barangay Sitio Maraag / Sudlon II (OSM point
  /// ≈ 123.7847, 10.3796) — are comfortably inside.
  ///
  /// Format: `left longitude, top latitude, right longitude, bottom latitude`
  /// (Nominatim's `viewbox` param; opposite-corner order does not matter).
  ///
  /// `bounded=1` is used alongside this box, which strictly excludes results
  /// outside.  That is intentional for this capstone's pilot scope (Section 4:
  /// "single-sitio pilot, not barangay/city-wide").  During the pilot every
  /// valid farm location is inside Cebu City, so a hard boundary prevents
  /// accidental placement of a farm in a different province — a concrete data
  /// integrity problem that was observed in testing ("sudlon" returning
  /// Surigao del Norte / Bohol results instead of Sudlon II, Cebu City).
  ///
  /// The one downside of `bounded=1` is that a search for a genuinely
  /// out-of-box place returns zero results.  That is acceptable here because:
  ///   1. The farmer can always drag the map to the out-of-box location
  ///      directly (raw coordinates are stored, the search bar is optional).
  ///   2. If the pilot later expands beyond Cebu City, widening is a
  ///      one-line change: update this constant (or pass a custom [viewbox]).
  static const String cebuPilotViewbox = '123.75,10.17,123.98,10.50';
  GeocodingService({
    http.Client? client,
    this.minInterval = const Duration(milliseconds: 1000),
  }) : _client = client ?? http.Client();

  static const String baseUrl = 'https://nominatim.openstreetmap.org';

  /// Identifies this app to Nominatim as required by their usage policy.
  static const String userAgent = 'FarmSpot/1.0 (student capstone project)';

  static const Duration _timeout = Duration(seconds: 8);

  final http.Client _client;
  final Duration minInterval;
  DateTime? _lastRequestAt;

  /// Reverse-geocodes a point to a short, human-readable address
  /// (e.g. "Sitio Maraag, Barangay Sudlon II, Cebu City").
  /// Returns `null` on any failure so callers can fall back to coordinates.
  Future<String?> reverseGeocode(LatLng point) async {
    final uri = Uri.parse('$baseUrl/reverse').replace(
      queryParameters: {
        'format': 'json',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'zoom': '17',
        'addressdetails': '1',
      },
    );
    try {
      await _throttle();
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      return parseReverseResponse(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Forward-geocodes a free-form query, restricted to the Philippines
  /// (this app's entire user base) and to greater Cebu City by default
  /// (this app's pilot area), returning up to [limit] candidates.
  ///
  /// [viewbox] is Nominatim's preferred bounding box; [bounded] decides
  /// whether results are strictly limited to that box (`true`, the default —
  /// see [cebuPilotViewbox] for the reasoning) or merely biased towards it.
  Future<List<GeocodePlace>> search(
    String query, {
    int limit = 5,
    String viewbox = cebuPilotViewbox,
    bool bounded = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final uri = Uri.parse('$baseUrl/search').replace(
      queryParameters: {
        'format': 'json',
        'q': q,
        'countrycodes': 'ph',
        'limit': '$limit',
        'viewbox': viewbox,
        'bounded': bounded ? '1' : '0',
      },
    );
    try {
      await _throttle();
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(_timeout);
      if (response.statusCode != 200) return const [];
      return parseSearchResponse(jsonDecode(response.body));
    } catch (_) {
      return const [];
    }
  }

  Future<void> close() async => _client.close();

  Map<String, String> _headers() => {
        'User-Agent': userAgent,
        'Accept': 'application/json',
      };

  /// Enforces Nominatim's 1 request/second policy even if callers debounce
  /// imperfectly.
  Future<void> _throttle() async {
    final last = _lastRequestAt;
    final now = DateTime.now();
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < minInterval) {
        await Future<void>.delayed(minInterval - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  /// Builds a compact local address from Nominatim's structured `address`
  /// object, falling back to the full display_name (minus the postcode).
  static String? parseReverseResponse(Map<String, dynamic> data) {
    const order = [
      'road',
      'neighbourhood',
      'hamlet',
      'village',
      'suburb',
      'municipality',
      'town',
      'city',
      'state_district',
      'region',
      'province',
    ];
    final address = data['address'];
    if (address is Map) {
      final parts = <String>[];
      for (final key in order) {
        final value = address[key];
        if (value is String && value.trim().isNotEmpty) {
          parts.add(value.trim());
        }
      }
      if (parts.isNotEmpty) return parts.take(4).join(', ');
    }

    final display = data['display_name']?.toString();
    if (display != null && display.trim().isNotEmpty) {
      return display
          .split(', ')
          .where((p) => !RegExp(r'^\d{4,6}$').hasMatch(p))
          .join(', ');
    }
    return null;
  }

  static List<GeocodePlace> parseSearchResponse(dynamic body) {
    if (body is! List) return const [];
    final places = <GeocodePlace>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      final lat = double.tryParse(item['lat']?.toString() ?? '');
      final lon = double.tryParse(item['lon']?.toString() ?? '');
      final name = item['display_name']?.toString();
      if (lat != null && lon != null && name != null && name.isNotEmpty) {
        places.add(GeocodePlace(
          displayName: name,
          latitude: lat,
          longitude: lon,
        ));
      }
    }
    return places;
  }
}