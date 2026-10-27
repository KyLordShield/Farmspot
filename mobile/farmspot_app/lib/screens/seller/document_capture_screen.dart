import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../../services/live_camera.dart';

/// Keeps capture in Farmspot instead of backgrounding it behind another app.
/// Releases camera resources before the caller starts OCR.
class DocumentCaptureScreen extends StatefulWidget {
  final Future<LiveCamera?> Function() openCamera;
  const DocumentCaptureScreen({super.key, this.openCamera = createLiveCamera});

  @override
  State<DocumentCaptureScreen> createState() => _DocumentCaptureScreenState();
}

class _DocumentCaptureScreenState extends State<DocumentCaptureScreen>
    with WidgetsBindingObserver {
  LiveCamera? _camera;
  Future<void>? _closing;
  bool _opening = false;
  bool _capturing = false;
  bool _active = true;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<void> _open() async {
    if (_opening || _camera != null || !_active || _capturing) return;
    final generation = _generation;
    setState(() {
      _opening = true;
      _error = null;
    });
    LiveCamera? camera;
    try {
      await _closing;
      if (mounted && _active && generation == _generation) {
        camera = await widget.openCamera();
      }
    } catch (_) {
      // Show the same actionable retry state for permissions and hardware errors.
    }
    if (!mounted || !_active || generation != _generation) {
      await camera?.dispose();
      if (mounted) {
        setState(() => _opening = false);
        if (_active) _open();
      }
      return;
    }
    setState(() {
      _opening = false;
      _camera = camera;
      if (camera == null) {
        _error =
            'Could not open the camera. Allow camera access and try again.';
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _generation++;
      final camera = _camera;
      setState(() => _camera = null);
      _closing = camera?.dispose() ?? _closing;
      await _closing;
    } else {
      _open();
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final XFile? photo = await camera.capture();
      if (!mounted) return;
      if (!_active || _camera != camera) {
        setState(() => _capturing = false);
        if (_active) _open();
        return;
      }
      if (photo == null) throw StateError('No photo');
      // Remove the preview before closing its underlying controller.
      setState(() => _camera = null);
      await camera.dispose();
      if (mounted) Navigator.of(context).pop(photo);
    } catch (_) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'Could not take the photo. Please try again.';
        });
        if (_camera == null) _open();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_capturing,
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Photograph document')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Fill the view with the document. Keep all text sharp and avoid glare.',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Center(
                child: _camera != null
                    ? _camera!.buildPreview()
                    : _opening || _capturing
                    ? const CircularProgressIndicator()
                    : const Icon(
                        Icons.no_photography_outlined,
                        color: Colors.white,
                        size: 64,
                      ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: _camera == null && !_opening && !_capturing
                  ? FilledButton(
                      onPressed: _open,
                      child: const Text('Retry camera'),
                    )
                  : FilledButton.icon(
                      onPressed: _camera == null || _capturing
                          ? null
                          : _capture,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Take photo'),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
