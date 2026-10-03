import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../theme.dart';

/// The single OpenStreetMap tile layer used by every FarmSpot map.
///
/// Three things are tuned for the field, where the phone is usually on mobile
/// data rather than WiFi:
///
/// - `panBuffer: 3` (flutter_map defaults to 1) fetches tiles well outside the
///   visible viewport. On a slow link the old value left a ring of unloaded
///   grey around wherever the farmer had just panned, which read as a broken
///   map. Fetching ahead means the area they are moving into is already there.
/// - `NetworkTileProvider(silenceExceptions: true)` turns a failed tile into a
///   blank tile instead of a thrown error. A single dropped request then cannot
///   bubble an exception up through the map widget and abort the rest of the
///   screen's tiles.
/// - `keepBuffer: 2` retains the previous zoom levels, so panning back over
///   ground the farmer already walked does not re-download.
class MapTileLayer extends StatelessWidget {
  final int panBuffer;
  final int keepBuffer;

  const MapTileLayer({
    super.key,
    this.panBuffer = 3,
    this.keepBuffer = 2,
  });

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.cloudsync.farmspot_app',
      panBuffer: panBuffer,
      keepBuffer: keepBuffer,
      tileProvider: NetworkTileProvider(silenceExceptions: true),
    );
  }
}

/// Light placeholder painted underneath a map until real tiles arrive.
///
/// The stock `MapOptions.backgroundColor` is a flat grey, which on a slow
/// connection looks like a dead map rather than a loading one. A soft tinted
/// wash plus a faint grid reads as "still working" and keeps the farmer's pin
/// and controls legible while the tiles stream in.
class MapLoadingBackground extends StatelessWidget {
  final Widget child;

  const MapLoadingBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF3F7F1),
      child: CustomPaint(
        painter: const _GridPainter(),
        child: child,
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryGreen.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    const step = 40.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}