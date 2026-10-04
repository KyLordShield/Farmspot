import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Buyers' location + straight-line "as the crow flies" distance helpers.
/// The distance math is the same haversine-based `latlong2.Distance` the Map
/// screen uses for its pins — reused here for the client-side "Nearest" sort
/// on the search results grid. No backend call is made per sort toggle.
class LocationService {
  /// Cebu City, used when GPS is unavailable or denied. Exposed as a constant
  /// so callers that must NOT block on a location lookup can anchor distance
  /// math synchronously instead of awaiting [defaultBuyerPosition].
  static const fallbackPosition = LatLng(10.3178, 123.8742);

  /// Fallback buyer position — Cebu City when GPS is unavailable or denied.
  /// Never throws: any geolocator failure (permission denied, services off,
  /// missing plugin, no fix) falls back to this center so distance sorting
  /// always has an anchor.
  static Future<LatLng> defaultBuyerPosition() async {
    try {
      await GeolocatorPlatform.instance.isLocationServiceEnabled();
      if (await GeolocatorPlatform.instance.checkPermission() ==
          LocationPermission.deniedForever) {
        return const LatLng(10.3178, 123.8742);
      }
      final pos = await GeolocatorPlatform.instance.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return const LatLng(10.3178, 123.8742);
    }
  }

  /// Great-circle distance between two points in kilometers.
  static double distanceKm(LatLng a, LatLng b) {
    return const Distance().as(LengthUnit.Kilometer, a, b);
  }

  /// Same label format as the Map screen's pin distances.
  static String distanceLabel(double km) {
    if (km < 0.1) return 'under 100 m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  /// Best-effort real fix for image search, WITHOUT the Cebu fallback.
  ///
  /// Returns null when the device cannot give a trustworthy position
  /// (permission denied, location services off, no fix within
  /// [timeout]). Callers use null to mean "no distances" and sort by
  /// detection confidence instead. Distinct from [defaultBuyerPosition],
  /// which always returns a position so text search keeps its existing
  /// behaviour of sorting against the fallback city.
  ///
  /// The timeout is what keeps a slow or wedged GPS from blocking the
  /// results screen: geolocator's own future can hang indefinitely, so
  /// this races it and gives up rather than leaving the caller waiting.
  static Future<LatLng?> tryBuyerPosition({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    // The timeout wraps the WHOLE lookup, not just the fix. Any of the three
    // geolocator calls can hang (a wedged platform channel never answers), and
    // a partially-timed-out version would still leave the caller waiting
    // forever on whichever call stalls first.
    return _lookupPosition().timeout(
      timeout,
      onTimeout: () => null,
    );
  }

  static Future<LatLng?> _lookupPosition() async {
    try {
      if (!await GeolocatorPlatform.instance.isLocationServiceEnabled()) {
        return null;
      }
      final permission = await GeolocatorPlatform.instance.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await GeolocatorPlatform.instance.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }
}