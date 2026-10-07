import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

/// A live camera that can paint a preview widget and snap one photo.
///
/// The default implementation wraps the `camera` plugin; widget tests inject a
/// fake so the capture flow is exerciseable headless.
abstract class LiveCamera {
  /// Paints the live feed. Must only be called after initialisation.
  Widget buildPreview();

  /// Takes one photo. Returns null if the shutter was skipped (unlikely for a
  /// still camera; exists so callers can re-try instead of crashing).
  Future<XFile?> capture();

  /// Switches to the other lens (front <-> back). Returns a replacement camera
  /// that already owns the resources; always dispose the returned camera too.
  /// Returns null when the device has only one lens, in which case the current
  /// camera stays active.
  Future<LiveCamera?> flip();

  /// Releases the camera resources.
  Future<void> dispose();
}

/// Opens the device camera and returns a ready [LiveCamera], or null when
/// there is no camera, permission is denied, or the platform has no camera
/// support (widget tests, desktops). The static viewfinder stays as the
/// fallback in those cases.
Future<LiveCamera?> createLiveCamera({
  CameraLensDirection preferredLens = CameraLensDirection.back,
}) async {
  try {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return null;

    bool pickForLens(CameraDescription candidate) =>
        candidate.lensDirection == preferredLens;
    final description = cameras.firstWhere(pickForLens, orElse: () => cameras.first);

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await controller.initialize();
    if (!controller.value.isInitialized) {
      await controller.dispose();
      return null;
    }
    return _PluginLiveCamera(controller, cameras);
  } catch (_) {
    // No camera hardware, permission denied, or no plugin in tests.
    return null;
  }
}

/// [LiveCamera] backed by the `camera` plugin's [CameraController].
class _PluginLiveCamera implements LiveCamera {
  _PluginLiveCamera(this._controller, this._allCameras);

  final CameraController _controller;
  final List<CameraDescription> _allCameras;

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Future<XFile?> capture() => _controller.takePicture();

  @override
  Future<LiveCamera?> flip() async {
    final target = _allCameras.where((c) {
      return c.lensDirection != _controller.description.lensDirection;
    });
    if (target.isEmpty) return null;

    final next = CameraController(
      target.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await next.initialize();
    if (!next.value.isInitialized) {
      await next.dispose();
      return null;
    }
    return _PluginLiveCamera(next, _allCameras);
  }

  @override
  Future<void> dispose() => _controller.dispose();
}