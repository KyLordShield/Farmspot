import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../theme.dart';

/// The single OpenStreetMap tile layer used by every FarmSpot map.
///
/// Native maps share flutter_map's disk cache across screens and launches.
/// Keep the network provider stable while a map is mounted so updates to GPS,
/// pins, and route overlays reuse the same client and in-flight requests.
class MapTileLayer extends StatefulWidget {
  final int panBuffer;
  final int keepBuffer;

  const MapTileLayer({super.key, this.panBuffer = 1, this.keepBuffer = 2});

  @override
  State<MapTileLayer> createState() => _MapTileLayerState();
}

class _MapTileLayerState extends State<MapTileLayer> {
  // TileLayer owns and disposes the provider when it unmounts.
  late final _provider = NetworkTileProvider(
    silenceExceptions: true,
    attemptDecodeOfHttpErrorResponses: false,
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 128 * 1024 * 1024,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.cloudsync.farmspot_app',
      panBuffer: widget.panBuffer,
      keepBuffer: widget.keepBuffer,
      tileProvider: _provider,
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
      child: CustomPaint(painter: const _GridPainter(), child: child),
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
