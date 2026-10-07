import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:lottie/lottie.dart';
import '../models/farm_pin.dart';
import '../models/gallery_photo.dart';
import '../models/listing.dart';
import '../models/search_crop_group.dart';
import '../services/farm_service.dart';
import '../services/gallery_service.dart';
import '../services/image_detect_service.dart';
import '../services/listing_service.dart';
import '../services/live_camera.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/app_feedback.dart';
import 'search_results_screen.dart';

/// Screen 3 of the search flow: image (visual) search.
///
/// Opening the screen shows a clean white screen, then a real in-app camera
/// preview starts automatically. The shutter button snaps a photo, which is
/// sent to the local YOLO service (ml_service/app.py) via ImageDetectService;
/// every crop the model finds becomes a listing in the live results screen.
/// Sliding above the bottom of the screen is a gallery panel showing the
/// three latest photos from the device library — drag the handle up to expand
/// it into the full gallery and tap any photo to identify that instead. When
/// no camera exists or permission is denied, the white state explains and the
/// gallery panel stays as the way in.
enum _ImageSearchStep { capture, identifying }

enum _ImageCameraState { starting, ready, unavailable }

class ImageSearchScreen extends StatefulWidget {
  /// Test seam: replaces the YOLO call. Defaults to ImageDetectService.
  final Future<List<DetectedCrop>> Function(XFile photo)? detect;

  /// Test seam: replaces the live camera. Defaults to [createLiveCamera],
  /// which returns null (and drops to the unavailable state) when no camera is
  /// available — widget tests can inject a fake to exercise the live path.
  final Future<LiveCamera?> Function()? createCamera;

  /// Test seam: replaces the photo-library read. Defaults to
  /// [GalleryService.loadPhotos]; returns empty in tests without a seam.
  final Future<List<GalleryPhoto>> Function({int? limit})? loadPhotos;

  /// Forwarded to [SearchResultsScreen] so tests can inject fake loaders.
  final Future<List<Listing>> Function(String term)? loadResults;
  final Future<List<FarmPin>> Function()? loadFarms;

  /// Real GPS fix for the distance sort, or null when location is
  /// unavailable (image search then falls back to confidence order).
  /// Test seam; defaults to LocationService.tryBuyerPosition.
  final Future<LatLng?> Function()? loadBuyerPosition;

  const ImageSearchScreen({
    super.key,
    this.detect,
    this.createCamera,
    this.loadPhotos,
    this.loadResults,
    this.loadFarms,
    this.loadBuyerPosition,
  });

  @override
  State<ImageSearchScreen> createState() => _ImageSearchScreenState();
}

/// Gallery sheet extents as a fraction of the screen height.
const double _sheetMinFrac = 0.20;
const double _sheetMaxFrac = 0.72;

class _ImageSearchScreenState extends State<ImageSearchScreen> {
  _ImageSearchStep _step = _ImageSearchStep.capture;
  _ImageCameraState _cameraState = _ImageCameraState.starting;

  LiveCamera? _camera;
  List<GalleryPhoto> _recents = const <GalleryPhoto>[];
  List<GalleryPhoto> _all = const <GalleryPhoto>[];

  bool get _hasGalleryPhotos => _recents.isNotEmpty || _all.isNotEmpty;

  double get _sheetCollapsedHeight =>
      MediaQuery.sizeOf(context).height * _sheetMinFrac;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final createCamera = widget.createCamera ?? createLiveCamera;
    final camera = await createCamera();

    final loadPhotos = widget.loadPhotos ?? GalleryService.loadPhotos;
    final recents = await loadPhotos(limit: 3);
    final all = await loadPhotos();

    if (!mounted) return;
    setState(() {
      _camera = camera;
      _cameraState = camera != null
          ? _ImageCameraState.ready
          : _ImageCameraState.unavailable;
      _recents = recents.isEmpty ? all.take(3).toList() : recents;
      _all = all;
    });
  }

  Future<void> _retryCamera() async {
    setState(() => _cameraState = _ImageCameraState.starting);
    final createCamera = widget.createCamera ?? createLiveCamera;
    final camera = await createCamera();
    if (!mounted) return;
    setState(() {
      _camera = camera;
      _cameraState = camera != null
          ? _ImageCameraState.ready
          : _ImageCameraState.unavailable;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBackground,
      body: SafeArea(
        child: switch (_step) {
          _ImageSearchStep.capture => _buildCapture(),
          _ImageSearchStep.identifying => Column(
            children: [
              _buildAppBar(),
              Expanded(child: _buildScanning()),
            ],
          ),
        },
      ),
    );
  }

  Widget _buildCapture() {
    return switch (_cameraState) {
      _ImageCameraState.starting => _buildStarting(),
      _ImageCameraState.ready => _buildLive(),
      _ImageCameraState.unavailable => _buildUnavailable(),
    };
  }

  /// Clean white transition while the camera finishes initialising — never any
  /// fake viewfinder or picker buttons on the way to the live preview.
  Widget _buildStarting() {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          _buildAppBar(),
          const Expanded(
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The live camera preview with the shutter above the gallery panel.
  Widget _buildLive() {
    final camera = _camera!;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(child: camera.buildPreview()),
        // Pin the title strip to the top. As a bare non-positioned child it
        // would be stretched to fill the whole stack, which both dims the
        // camera and vertically centers the bar in the middle of the screen.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildAppBar(),
        ),
        _buildShutterArea(),
        if (_hasGalleryPhotos) _buildGalleryPanel(),
      ],
    );
  }

  /// No camera hardware / permission denied: kept minimal — a short message,
  /// a retry, and the gallery panel as the way to pick a photo.
  Widget _buildUnavailable() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.white,
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    28,
                    0,
                    28,
                    _hasGalleryPhotos ? _sheetCollapsedHeight + 8 : 24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.no_photography_outlined,
                        size: 44,
                        color: Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Camera isn't available. Pick a photo from your "
                        'gallery instead.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black45, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _retryCamera,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_hasGalleryPhotos) _buildGalleryPanel(),
      ],
    );
  }

  /// Shutter control that floats above the collapsed gallery panel.
  Widget _buildShutterArea() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: _sheetCollapsedHeight + 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Aim at the crop, then tap the shutter',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('image-search-shutter'),
              customBorder: const CircleBorder(),
              onTap: _captureFromLiveCamera,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(
                  Icons.camera_alt,
                  size: 32,
                  color: AppColors.primaryGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryPanel() {
    return _GalleryPanel(
      recents: _recents,
      all: _all,
      onPickPhoto: _onPickPhoto,
      minFraction: _sheetMinFrac,
      maxFraction: _sheetMaxFrac,
    );
  }

  Widget _buildAppBar() {
    final overCamera = _cameraState == _ImageCameraState.ready;
    final foreground = overCamera ? Colors.white : Colors.black87;
    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back),
            color: foreground,
            tooltip: 'Back',
          ),
          Text(
            'Identify crop',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: foreground,
            ),
          ),
        ],
      ),
    );
    if (!overCamera) return bar;
    return Container(color: Colors.black26, child: bar);
  }

  /// The Image scan animation shown while the YOLO service runs.
  Widget _buildScanning() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset(
            'assets/animations/Image scan.lottie',
            width: 240,
            height: 240,
            repeat: true,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryGreen,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Scanning Image',
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

  Future<void> _onPickPhoto(GalleryPhoto photo) async {
    XFile? file;
    try {
      file = await photo.file();
    } catch (_) {
      file = null;
    }
    if (!mounted) return;
    if (file == null) {
      showFarmSpotSnackBar(context, 'Could not open that photo.', isError: true);
      return;
    }
    await _identifyPhoto(file);
  }

  Future<void> _captureFromLiveCamera() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      final shot = await camera.capture();
      if (!mounted) return;
      if (shot == null) {
        showFarmSpotSnackBar(
          context,
          'Could not take a photo. Try again.',
          isError: true,
        );
        return;
      }
      await _identifyPhoto(shot);
    } catch (_) {
      if (!mounted) return;
      showFarmSpotSnackBar(
        context,
        'Could not take a photo. Try again.',
        isError: true,
      );
    }
  }

  /// Sends [photo] to the YOLO service, then jumps straight to the live
  /// results screen (one section per crop the model found). Bounces back to
  /// capture with an error toast if no crop was confidently identified.
  Future<void> _identifyPhoto(XFile photo) async {
    setState(() => _step = _ImageSearchStep.identifying);

    final detect = widget.detect ?? (p) => ImageDetectService.detectCrops(p);
    final crops = await detect(photo);
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

    // Every found crop contributes to ONE mixed results list (with its alias
    // terms so a "kamatis" also surfaces listings titled "Tomato"), sorted
    // nearest-farm-first inside SearchResultsScreen. Detection confidences
    // ride along so each card can show which crop matched and how sure the
    // model was.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(
          query: crops.first.name,
          groups: [
            for (final crop in crops) SearchCropGroup.resolve(crop.name),
          ],
          detectionConfidences: [
            for (final crop in crops)
              (SearchCropGroup.resolve(crop.name).title, crop.confidence),
          ],
          loadResults:
              widget.loadResults ?? (t) => ListingService.fetchListings(search: t),
          loadFarms: widget.loadFarms ?? FarmService.fetchPublicFarms,
          loadBuyerPosition:
              widget.loadBuyerPosition ?? LocationService.tryBuyerPosition,
        ),
      ),
    );
    // Back from results -> ready for the next photo.
    if (!mounted) return;
    setState(() => _step = _ImageSearchStep.capture);
  }
}

/// The bottom gallery sheet: three latest photos when collapsed, drag the
/// handle up (or tap the chevron) to expand into the full gallery grid.
class _GalleryPanel extends StatefulWidget {
  const _GalleryPanel({
    required this.recents,
    required this.all,
    required this.onPickPhoto,
    required this.minFraction,
    required this.maxFraction,
  });

  final List<GalleryPhoto> recents;
  final List<GalleryPhoto> all;
  final ValueChanged<GalleryPhoto> onPickPhoto;
  final double minFraction;
  final double maxFraction;

  @override
  State<_GalleryPanel> createState() => _GalleryPanelState();
}

class _GalleryPanelState extends State<_GalleryPanel> {
  double _extent = 0; // 0 = collapsed strip, 1 = expanded grid.
  bool _dragging = false;

  bool get _expanded => _extent >= 0.45;

  double _minHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height * widget.minFraction;

  double _maxHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height * widget.maxFraction;

  List<GalleryPhoto> get _gridPhotos =>
      widget.all.isEmpty ? widget.recents : widget.all;

  /// Height of the three-thumbnail strip once the panel's header (~68 px) is
  /// reserved, clamped so short screens still fit inside the collapsed panel.
  double _stripHeight(BuildContext context) => (MediaQuery.sizeOf(context)
          .height *
          widget.minFraction -
      68)
      .clamp(52.0, 100.0);

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragging = true;
      final pxRange = _maxHeight(context) - _minHeight(context);
      _extent = (_extent - details.delta.dy / pxRange).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _dragging = false;
      final velocity = details.primaryVelocity ?? 0;
      if (velocity < -200) {
        _extent = 1;
      } else if (velocity > 200) {
        _extent = 0;
      } else {
        _extent = _extent >= 0.5 ? 1 : 0;
      }
    });
  }

  void _toggle() {
    if (_dragging) return;
    setState(() => _extent = _expanded ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final height =
        _minHeight(context) + (_maxHeight(context) - _minHeight(context)) * _extent;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: _dragging
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: height,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(),
            if (_expanded)
              Expanded(child: _buildGrid())
            else
              _buildStrip(_stripHeight(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return GestureDetector(
      key: const Key('gallery-sheet-handle'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.mutedGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _expanded ? 'All photos' : 'Recent photos',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            IconButton(
              tooltip: _expanded ? 'Collapse gallery' : 'Open full gallery',
              onPressed: _toggle,
              icon: Icon(
                _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrip(double stripHeight) {
    return SizedBox(
      height: stripHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(
          children: [
            for (final photo in widget.recents.take(3))
              AspectRatio(
                aspectRatio: 1,
                child: _GalleryThumb(photo: photo, onTap: widget.onPickPhoto),
              ),
            if (widget.recents.length < 3) const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: GridView.builder(
        key: const Key('image-search-gallery-grid'),
        itemCount: _gridPhotos.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemBuilder: (context, index) =>
            _GalleryThumb(photo: _gridPhotos[index], onTap: widget.onPickPhoto),
      ),
    );
  }
}

/// A square thumbnail tile that loads its bytes lazily.
class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.photo, required this.onTap});

  final GalleryPhoto photo;
  final ValueChanged<GalleryPhoto> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('gallery-photo-${photo.id}'),
          onTap: () => onTap(photo),
          child: FutureBuilder<Uint8List?>(
            future: photo.thumb(),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return Container(
                  color: AppColors.fieldBackground,
                  child: const Icon(Icons.image_outlined, color: Colors.black26),
                );
              }
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.fieldBackground,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.black26,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}