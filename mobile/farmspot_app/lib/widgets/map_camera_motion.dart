import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Brief camera movement shared by the app's location controls.
mixin MapCameraMotion<T extends StatefulWidget> on State<T>, TickerProvider {
  AnimationController? _cameraMotion;

  void moveToLocation(MapController map, LatLng target, double zoom) {
    stopCameraMotion();
    if (MediaQuery.disableAnimationsOf(context)) {
      map.move(target, zoom);
      return;
    }

    final start = map.camera;
    final longitudeDelta =
        (target.longitude - start.center.longitude + 540) % 360 - 180;
    _cameraMotion =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 220),
          )
          ..addListener(() {
            final t = Curves.easeOutCubic.transform(_cameraMotion!.value);
            final longitude = start.center.longitude + longitudeDelta * t;
            map.move(
              LatLng(
                lerpDouble(start.center.latitude, target.latitude, t)!,
                (longitude + 540) % 360 - 180,
              ),
              lerpDouble(start.zoom, zoom, t)!,
            );
          })
          ..forward();
  }

  void stopCameraMotion() {
    _cameraMotion?.dispose();
    _cameraMotion = null;
  }

  @override
  void dispose() {
    stopCameraMotion();
    super.dispose();
  }
}
