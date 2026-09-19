import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Buyers' location + straight-line "as the crow flies" distance helpers.
/// The distance math is the same haversine-based `latlong2.Distance` the Map
/// screen uses for its pins — reused here for the client-side "Nearest" sort
/// on the search results grid. No backend call is made per sort toggle.
class LocationService {
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
}