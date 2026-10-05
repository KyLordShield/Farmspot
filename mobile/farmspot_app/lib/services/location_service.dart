import 'dart:async';

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
  ///
  /// Asks for permission before falling back. A buyer who has never been asked
  /// has never granted, and every distance measured from this anchor is a
  /// confident number about a place they are not at.
  static Future<LatLng> defaultBuyerPosition() async {
    return await tryBuyerPosition() ?? fallbackPosition;
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

  /// Best-effort real fix for BOTH search modes, WITHOUT the Cebu fallback.
  ///
  /// Asks the OS for permission when it has not been answered yet. Returning
  /// null on a plain [LocationPermission.denied] without asking first is what
  /// left a buyer with location switched on staring at "Distance unavailable"
  /// and no prompt anywhere: the app never requested, so it was never granted,
  /// so it correctly reported no fix. Distinct from [defaultBuyerPosition],
  /// which asks first and answers with the fallback city when refused.
  ///
  /// Returns null when the device cannot give a trustworthy position
  /// (permission refused, location services off, no fix within [fixTimeout]).
  /// Callers use null to mean "no distances" rather than a measured guess.
  ///
  /// The [fixTimeout] deliberately covers ONLY the GPS fix, never the
  /// permission request. A permission dialog takes as long as the buyer takes
  /// to read and answer it; a timeout across it gives up while the dialog is
  /// still on screen, the caller reports "no location", and the buyer grants
  /// permission to a screen that has already given up on it.
  static Future<LatLng?> tryBuyerPosition({
    Duration fixTimeout = const Duration(seconds: 6),
    Duration permissionTimeout = const Duration(minutes: 2),
  }) async {
    try {
      if (!await GeolocatorPlatform.instance.isLocationServiceEnabled()) {
        return null;
      }
      var permission = await GeolocatorPlatform.instance.checkPermission();
      if (permission == LocationPermission.denied) {
        // The only state that is still answerable. deniedForever is not: the
        // OS will not show a dialog again, and silently returning null there
        // is indistinguishable from the buyer having said no.
        permission = await GeolocatorPlatform.instance
            .requestPermission()
            .timeout(
              permissionTimeout,
              onTimeout: () => LocationPermission.deniedForever,
            );
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
      // Only the fix is raced. geolocator's future can hang indefinitely on a
      // wedged platform channel or a GPS that never locks, and this is what
      // keeps that from stalling the results screen.
      final pos = await GeolocatorPlatform.instance
          .getCurrentPosition()
          .timeout(fixTimeout, onTimeout: () => _throwTimeout());
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  static Never _throwTimeout() {
    throw TimeoutException('no GPS fix');
  }
}
