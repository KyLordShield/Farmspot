import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:farmspot_app/services/routing_service.dart';

/// Throwaway live integration test (run manually, not part of the suite):
/// proves the shipped RoutingService works against the real FOSSGIS OSRM
/// endpoints for a real Cebu route, and that car vs foot genuinely differ.
void main() {
  test('live: car and foot routes from Cebu City to Sitio Maraag', () async {
    // Fuente Osmeña, Cebu City -> near Sitio Maraag (Sudlon II).
    const from = LatLng(10.3157, 123.8854);
    const to = LatLng(10.3796, 123.7847);

    final service = RoutingService();
    try {
      final stopwatch = Stopwatch()..start();
      final car = await service.getRoute(from: from, to: to, profile: 'car');
      final foot = await service.getRoute(from: from, to: to, profile: 'foot');
      stopwatch.stop();

      expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)),
          reason: 'the built-in throttle must space the two live calls 1s apart');

      expect(car, isNotNull, reason: 'the real car endpoint must return a route');
      expect(foot, isNotNull, reason: 'the real foot endpoint must return a route');

      expect(car!.distanceMeters, greaterThan(0));
      expect(car.durationSeconds, greaterThan(0));
      expect(car.geometry, isNotEmpty);
      expect(car.steps, isNotEmpty);
      for (final step in car.steps) {
        expect(step.instruction, isNotEmpty,
            reason: 'every step must carry a (synthesized) instruction text');
      }

      // The profiles must genuinely differ — the whole point of keeping both.
      expect(car.distanceMeters, isNot(foot!.distanceMeters));
      expect(car.durationSeconds, isNot(foot.durationSeconds));
      expect(car.durationSeconds, lessThan(foot.durationSeconds),
          reason: 'driving must be faster than walking');
      expect(car.geometry.length, isNot(equals(foot.geometry.length)),
          reason: 'car and foot must trace different paths');
    } finally {
      await service.close();
    }
  });
}