import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../models/farm_pin.dart';
import '../models/listing.dart';
import '../models/search_crop_group.dart';
import '../services/farm_service.dart';
import '../services/image_detect_service.dart';
import '../services/listing_service.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/app_feedback.dart';
import 'search_results_screen.dart';

/// Screen 3 of the search flow: image (visual) search.
///
/// The camera/gallery buttons open the real device picker, the captured photo
/// is sent to the local YOLO service (ml_service/app.py) via
/// ImageDetectService. Every crop the model finds becomes a section on the
/// live results screen (SearchResultsScreen multi-crop mode), so the flow is:
/// photo -> scan -> straight to results (no "crop detected" interstitial).
enum _ImageSearchStep { capture, identifying }

class ImageSearchScreen extends StatefulWidget {
  /// Test seam: replaces the real device picker. Defaults to ImagePicker.
  final Future<XFile?> Function(ImageSource source)? pickImage;

  /// Test seam: replaces the YOLO call. Defaults to ImageDetectService.
  final Future<List<DetectedCrop>> Function(XFile photo)? detect;

  /// Forwarded to [SearchResultsScreen] so tests can inject fake loaders.
  final Future<List<Listing>> Function(String term)? loadResults;
  final Future<LatLng> Function()? loadPosition;
  final Future<List<FarmPin>> Function()? loadFarms;

  const ImageSearchScreen({
    super.key,
    this.pickImage,
    this.detect,
    this.loadResults,
    this.loadPosition,
    this.loadFarms,
  });

  @override
  State<ImageSearchScreen> createState() => _ImageSearchScreenState();
}

class _ImageSearchScreenState extends State<ImageSearchScreen> {
  _ImageSearchStep _step = _ImageSearchStep.capture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBackground,
      body: SafeArea(
        child: switch (_step) {
          _ImageSearchStep.capture => _buildCapture(),
          _ImageSearchStep.identifying => _buildIdentifying(),
        },
      ),
    );
  }

  /// Step 1 — Capture: static dashed-corner viewfinder + Camera / Gallery
  /// buttons.
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

  /// Step 2 — Identifying: shows a loading state while the YOLO service runs.
  Widget _buildIdentifying() {
    return Column(
      children: [
        _buildAppBar(),
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
            _step == _ImageSearchStep.capture ? 'Identify crop' : 'Identifying',
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

  /// Opens the device picker, uploads the photo to the YOLO service, then
  /// jumps straight to the live results screen (one section per crop the
  /// model found). Bounces back to capture with an error toast if no crop
  /// was confidently identified.
  Future<void> _identify({required ImageSource source}) async {
    final pick =
        widget.pickImage ?? (s) => ImagePicker().pickImage(source: s, imageQuality: 85);
    final picked = await pick(source);
    if (picked == null || !mounted) return;

    setState(() => _step = _ImageSearchStep.identifying);

    final detect =
        widget.detect ?? (photo) => ImageDetectService.detectCrops(photo);
    final crops = await detect(picked);
    if (!mounted) return;

    if (crops.isEmpty) {
      showFarmSpotSnackBar(
        context,
        'Could not identify the crop. Try a clearer photo.',
        isError: true,
      );
      setState(() => _step = _ImageSearchStep.capture);
      return;
    }

    // Every found crop becomes a results section (with its alias terms so a
    // "kamatis" also surfaces listings titled "Tomato"), each section sorted
    // nearest-first inside SearchResultsScreen.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(
          query: crops.first.name,
          groups: [for (final crop in crops) SearchCropGroup.resolve(crop.name)],
          loadResults:
              widget.loadResults ?? (t) => ListingService.fetchListings(search: t),
          loadPosition: widget.loadPosition ?? LocationService.defaultBuyerPosition,
          loadFarms: widget.loadFarms ?? FarmService.fetchPublicFarms,
        ),
      ),
    );
    // Back from results -> ready for the next photo.
    if (!mounted) return;
    setState(() => _step = _ImageSearchStep.capture);
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