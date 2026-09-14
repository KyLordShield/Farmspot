import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One turn-by-turn instruction along a route, with the length of that leg.
///
/// The OSRM demo servers return each step's `maneuver` (type/modifier) and the
/// street `name`, but not a free-text instruction (only some OSRM servers do).
/// `instruction` therefore prefers a server-provided `instruction` string when
/// one exists, otherwise falls back to a locally synthesized
/// "Turn left onto Bonbon-Sudlon Road"-style sentence from type+modifier+name.
class RouteStep {
  final String instruction;
  final double distanceMeters;

  /// Where this maneuver happens (parsed from OSRM's `maneuver.location`), used
  /// by the live journey to advance to the next turn as the walker passes it.
  /// Null when the server omits the location or the step is a synthetic one.
  final LatLng? position;

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    this.position,
  });
}

/// A complete routing result: totals, the polyline to draw on the map, and the
/// turn-by-turn steps.
class RoutePlan {
  final double distanceMeters;
  final double durationSeconds;

  /// Route geometry as lat/lng points (GeoJSON coordinates arrive as
  /// [longitude, latitude], reversed into the app's [LatLng] order here).
  final List<LatLng> geometry;

  final List<RouteStep> steps;

  const RoutePlan({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.geometry,
    required this.steps,
  });
}

/// Thin client over FOSSGIS's public OSRM demo routers
/// (routing.openstreetmap.de, no API key): `routed-car` and `routed-foot`,
/// both under the `/driving` profile.
///
/// The FOSSGIS usage policy asks for at most ~1 request/second and a
/// descriptive User-Agent, so — mirroring [GeocodingService] — every call
/// carries a User-Agent and consecutive requests are spaced at least
/// [minInterval] apart.
///
/// Every method is failure-tolerant: network errors, timeouts and malformed
/// responses all degrade to `null` so a caller can fall back to a straight
/// haversine estimate instead of crashing.
class RoutingService {
  RoutingService({
    http.Client? client,
    this.minInterval = const Duration(milliseconds: 1000),
  }) : _client = client ?? http.Client();

  static const String baseUrl = 'https://routing.openstreetmap.de';

  /// Identifies this app to the public routers as required by their policy.
  static const String userAgent = 'FarmSpot/1.0 (student capstone project)';

  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client;
  final Duration minInterval;
  DateTime? _lastRequestAt;

  /// Routes from [from] to [to]. [profile] is `'car'` or `'foot'` (anything
  /// else falls back to `'car'`), mapping to routed-car / routed-foot.
  ///
  /// Returns `null` on any failure (network, timeout, non-200, malformed body)
  /// so callers can degrade gracefully. Never throws.
  Future<RoutePlan?> getRoute({
    required LatLng from,
    required LatLng to,
    required String profile,
  }) async {
    final provider = profile == 'foot' ? 'foot' : 'car';
    // OSRM wants {lon},{lat};{lon},{lat} — longitude first.
    final uri =
        Uri.parse(
          '$baseUrl/routed-$provider/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
        ).replace(
          queryParameters: const {
            'overview': 'full',
            'geometries': 'geojson',
            'steps': 'true',
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
      return parseRouteResponse(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async => _client.close();

  Map<String, String> _headers() => {
    'User-Agent': userAgent,
    'Accept': 'application/json',
  };

  /// Enforces the ~1 request/second policy even if callers debounce
  /// imperfectly (same pattern as [GeocodingService._throttle]).
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

  /// Parses an OSRM v5 response into a [RoutePlan]. Returns `null` when the
  /// shape is missing the essentials (a route block with totals).
  static RoutePlan? parseRouteResponse(Map<String, dynamic> data) {
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final route = routes.first;
    if (route is! Map<String, dynamic>) return null;

    final distance = (route['distance'] as num?)?.toDouble();
    final duration = (route['duration'] as num?)?.toDouble();
    if (distance == null || duration == null) return null;

    var geometry = <LatLng>[];
    final geo = route['geometry'];
    if (geo is Map) {
      final coords = geo['coordinates'];
      if (coords is List) {
        geometry = <LatLng>[];
        for (final c in coords) {
          if (c is List && c.length >= 2) {
            final lon = (c[0] as num?)?.toDouble();
            final lat = (c[1] as num?)?.toDouble();
            if (lon != null && lat != null) {
              geometry.add(LatLng(lat, lon));
            }
          }
        }
      }
    }

    final steps = <RouteStep>[];
    final legs = route['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map<String, dynamic>) continue;
        final legSteps = leg['steps'];
        if (legSteps is! List) continue;
        for (final step in legSteps) {
          if (step is! Map<String, dynamic>) continue;
          final stepDistance = (step['distance'] as num?)?.toDouble() ?? 0;
          final maneuver = step['maneuver'];
          LatLng? location;
          if (maneuver is Map) {
            final raw = maneuver['location'];
            if (raw is List && raw.length >= 2) {
              final lon = (raw[0] as num?)?.toDouble();
              final lat = (raw[1] as num?)?.toDouble();
              if (lon != null && lat != null) {
                location = LatLng(lat, lon);
              }
            }
          }
          steps.add(
            RouteStep(
              instruction: _instructionFor(step),
              distanceMeters: stepDistance,
              position: location,
            ),
          );
        }
      }
    }

    return RoutePlan(
      distanceMeters: distance,
      durationSeconds: duration,
      geometry: geometry,
      steps: steps,
    );
  }

  /// Synthesizes a human-readable instruction from an OSRM step, preferring a
  /// server-provided `instruction` string when one is present.
  static String _instructionFor(Map<String, dynamic> step) {
    final serverText = step['instruction']?.toString();
    if (serverText != null && serverText.trim().isNotEmpty) {
      return serverText.trim();
    }

    final name = step['name'] is String ? (step['name'] as String).trim() : '';
    final maneuver = step['maneuver'];
    final type = maneuver is Map
        ? (maneuver['type'] as String?) ?? 'continue'
        : 'continue';
    final modifier = maneuver is Map
        ? (maneuver['modifier'] as String?) ?? ''
        : '';

    switch (type) {
      case 'depart':
        return name.isEmpty ? 'Depart' : 'Head out on $name';
      case 'arrive':
        return name.isEmpty ? 'Arrive at your destination' : 'Arrive at $name';
      case 'roundabout':
      case 'rotary':
        return name.isEmpty
            ? 'Enter the roundabout'
            : 'Enter the roundabout, take $name';
      case 'roundabout turn':
        return name.isEmpty
            ? 'At the roundabout, turn ${_modifierText(modifier)}'
            : 'At the roundabout, turn ${_modifierText(modifier)} onto $name';
      case 'merge':
        return name.isEmpty ? 'Merge' : 'Merge onto $name';
      case 'fork':
        return name.isEmpty
            ? 'Keep ${_modifierText(modifier)} at the fork'
            : 'Keep ${_modifierText(modifier)} at the fork, stay on $name';
      case 'on ramp':
        return name.isEmpty ? 'Take the ramp' : 'Take the ramp onto $name';
      case 'off ramp':
        return name.isEmpty ? 'Exit the ramp' : 'Exit the ramp onto $name';
      case 'end of road':
        return name.isEmpty
            ? 'Turn ${_modifierText(modifier)} at the end of the road'
            : 'Turn ${_modifierText(modifier)} at the end of the road onto $name';
      case 'new name':
        return name.isEmpty ? 'Continue' : 'Continue onto $name';
      case 'turn':
        if (modifier == 'straight') {
          return name.isEmpty
              ? 'Continue straight'
              : 'Continue straight onto $name';
        }
        return name.isEmpty
            ? 'Turn ${_modifierText(modifier)}'
            : 'Turn ${_modifierText(modifier)} onto $name';
      default:
        return name.isEmpty ? 'Continue' : 'Continue along $name';
    }
  }

  /// 'uturn' -> "make a U-turn" so a bare modifier reads naturally in text.
  static String _modifierText(String modifier) {
    if (modifier.isEmpty) return 'ahead';
    if (modifier == 'uturn') return 'make a U-turn';
    return modifier;
  }
}
