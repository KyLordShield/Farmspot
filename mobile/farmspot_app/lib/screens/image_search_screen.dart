import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_detect_service.dart';
import '../theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/search_widgets.dart';

/// Screen 3 of the search flow: image (visual) search, driven by a three
/// step state machine following the same enum + switch pattern as
/// FarmDirectionsScreen.
///
/// The camera/gallery buttons open the real device picker, the captured
/// photo is sent to the local YOLO service (ml_service/app.py) via
/// ImageDetectService, and the detected crop name drives the results step.
/// The results grid itself is still mock data until search wiring arrives.
enum _ImageSearchStep { capture, identifying, results }

class ImageSearchScreen extends StatefulWidget {
  const ImageSearchScreen({super.key});

  @override
  State<ImageSearchScreen> createState() => _ImageSearchScreenState();
}

class _ImageSearchScreenState extends State<ImageSearchScreen> {
  _ImageSearchStep _step = _ImageSearchStep.capture;

  /// Detected crop name once the YOLO service replies; null while identifying
  /// (drives whether the scanning or detected UI shows).
  String? _detectedCrop;
  double? _detectedConfidence;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBackground,
      body: SafeArea(
        child: switch (_step) {
          _ImageSearchStep.capture => _buildCapture(),
          _ImageSearchStep.identifying => _buildIdentifying(),
          _ImageSearchStep.results => _buildResults(),
        },
      ),
    );
  }

  /// Step 1 — Capture: static dashed-corner viewfinder + Camera / Gallery
  /// buttons (both fake; either advances to the identifying step).
  Widget _buildCapture() {
    return Column(
      children: [
        _buildAppBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              children: [
                const Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 0.9,
                      child: CustomPaint(
                        painter: _ViewfinderPainter(
                          color: AppColors.primaryGreen,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.photo_camera_outlined,
                                size: 48,
                                color: Colors.black26,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Point your camera at a crop or open a photo\nto identify it',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.black45,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _identify(source: ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      side: const BorderSide(color: AppColors.primaryGreen),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _identify(source: ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Use a clear, well-lit photo of a single crop for best results.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Step 2 — Identifying: shows a fake loading state, then after a short
  /// delay reveals a hardcoded detected result with correction + proceed
  /// actions.
  Widget _buildIdentifying() {
    return Column(
      children: [
        _buildAppBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: _detectedCrop == null ? _buildScanning() : _buildDetected(),
          ),
        ),
      ],
    );
  }

  Widget _buildScanning() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 150,
              height: 150,
              color: const Color(0xFFE9F1E7),
              child: const Icon(
                Icons.eco,
                size: 56,
                color: AppColors.primaryGreen,
              ),
            ),
          ),
          const SizedBox(height: 28),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'AI identifying crop...',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetected() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 150,
                    height: 150,
                    color: const Color(0xFFE9F1E7),
                    child: const Icon(
                      Icons.eco,
                      size: 56,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.primaryGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_detectedCrop!} detected',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(_detectedConfidence! * 100).round()}% sure this is ${_detectedCrop!}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _restart,
                  child: const Text(
                    'Not this?',
                    style: TextStyle(
                      color: AppColors.mutedGreen,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => setState(() => _step = _ImageSearchStep.results),
            icon: const Icon(Icons.view_list),
            label: const Text('Show Results \u2014 Nearest First'),
          ),
        ),
      ],
    );
  }

  /// Step 3 — Results: reuses the same 2x2 grid as the typed-results screen,
  /// keyed by the detected crop name, with a correction link and sort chips.
  Widget _buildResults() {
    return Column(
      children: [
        _buildAppBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              SearchResultsToolbar(
                sort: SearchSortMode.nearest,
                onSortChanged: (_) {
                  // Visual-only toggle in this mockup.
                },
                trailing: GestureDetector(
                  onTap: _restart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3EEDD),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 15,
                          color: AppColors.primaryGreen,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Not this?',
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildCountLine(),
              const SizedBox(height: 14),
              SearchResultGrid(
                items: mockSearchResults,
                onTap: (item) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${item.crop} from ${item.seller} — detail coming soon.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountLine() {
    return Row(
      children: [
        Container(
          width: 5,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${mockSearchResults.length} farms selling ${_detectedCrop!} '
            'near you',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            color: Colors.black87,
            tooltip: 'Back',
          ),
          Text(
            switch (_step) {
              _ImageSearchStep.capture => 'Identify crop',
              _ImageSearchStep.identifying => 'Identifying',
              _ImageSearchStep.results => _detectedCrop ?? '',
            },
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          if (_step == _ImageSearchStep.capture)
            const Icon(Icons.photo_camera_outlined,
                color: AppColors.primaryGreen),
        ],
      ),
    );
  }

  /// Opens the device picker, uploads the photo to the YOLO service, and
  /// reveals the detected crop name — or bounces back with an error toast.
  Future<void> _identify({required ImageSource source}) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _step = _ImageSearchStep.identifying;
      _detectedCrop = null;
      _detectedConfidence = null;
    });

    final crop = await ImageDetectService.detectCrop(picked);
    if (!mounted) return;

    if (crop == null) {
      showFarmSpotSnackBar(
        context,
        'Could not identify the crop. Try a clearer photo.',
        isError: true,
      );
      setState(() => _step = _ImageSearchStep.capture);
      return;
    }

    setState(() {
      _detectedCrop = crop.name;
      _detectedConfidence = crop.confidence;
    });
  }

  /// Returns to the capture step after a correction link or failed attempt.
  void _restart() {
    setState(() {
      _step = _ImageSearchStep.capture;
      _detectedCrop = null;
      _detectedConfidence = null;
    });
  }
}

/// Draws dashed corner brackets around the viewfinder box (the classic
/// camera-framing affordance) — purely decorative, no real preview.
class _ViewfinderPainter extends CustomPainter {
  final Color color;

  const _ViewfinderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const bracket = 28.0;
    const inset = 0.0;

    Offset p0 = Offset(inset, inset);
    Offset p1 = Offset(inset + bracket, inset);
    Offset p2 = Offset(inset, inset + bracket);

    // Top-left corner.
    canvas.drawLine(p0, p1, paint);
    canvas.drawLine(p0, p2, paint);

    // Top-right corner.
    p0 = Offset(size.width - inset, inset);
    p1 = Offset(size.width - inset - bracket, inset);
    p2 = Offset(size.width - inset, inset + bracket);
    canvas.drawLine(p0, p1, paint);
    canvas.drawLine(p0, p2, paint);

    // Bottom-left corner.
    p0 = Offset(inset, size.height - inset);
    p1 = Offset(inset + bracket, size.height - inset);
    p2 = Offset(inset, size.height - inset - bracket);
    canvas.drawLine(p0, p1, paint);
    canvas.drawLine(p0, p2, paint);

    // Bottom-right corner.
    p0 = Offset(size.width - inset, size.height - inset);
    p1 = Offset(size.width - inset - bracket, size.height - inset);
    p2 = Offset(size.width - inset, size.height - inset - bracket);
    canvas.drawLine(p0, p1, paint);
    canvas.drawLine(p0, p2, paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) =>
      oldDelegate.color != color;
}