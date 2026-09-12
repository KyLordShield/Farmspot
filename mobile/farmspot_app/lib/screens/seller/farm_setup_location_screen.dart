import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/farm_setup_data.dart';
import '../../../services/farm_service.dart';
import '../../../services/geocoding_service.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import 'farm_setup_complete_screen.dart';

class FarmSetupLocationScreen extends StatefulWidget {
  final FarmSetupData farmSetupData;

  /// Injectable for tests; a real Nominatim-backed service is created when
  /// omitted.
  final GeocodingService? geocodingService;

  const FarmSetupLocationScreen({
    super.key,
    required this.farmSetupData,
    this.geocodingService,
  });

  @override
  State<FarmSetupLocationScreen> createState() =>
      _FarmSetupLocationScreenState();
}

class _FarmSetupLocationScreenState extends State<FarmSetupLocationScreen> {
  /// Sitio Maraag / Cebu City — the reasonable default shown when the device
  /// GPS is unavailable (permission denied, services off, or a fix failing).
  static const LatLng _fallbackCenter = LatLng(10.3178, 123.8742);
  static const double _initialZoom = 15.5;

  /// Nominatim usage policy allows ~1 request/second; this debounce means a
  /// reverse lookup only fires after the pin has settled, never mid-drag.
  static const Duration _reverseDebounce = Duration(milliseconds: 700);

  final MapController _mapController = MapController();

  late final GeocodingService _geocodingService;
  final TextEditingController _searchController = TextEditingController();

  LatLng _markerPosition = _fallbackCenter;
  bool _isLocating = false;
  String? _gpsNotice;
  String? _errorMessage;
  String? _submitError;
  bool _isSubmitting = false;

  /// True while the farmer is dragging the marker; while it is, map
  /// panning/rotation is disabled so the two gestures never fight.
  bool _draggingMarker = false;

  /// Human-readable address of the current pin (best-effort). When null, the
  /// screen shows the raw coordinates instead — the farmer can always continue.
  String? _address;
  bool _isReverseGeocoding = false;
  Timer? _reverseDebounceTimer;

  /// Forward-geocoding search state.
  bool _isSearching = false;
  List<GeocodePlace>? _searchResults;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _geocodingService =
        widget.geocodingService ?? GeocodingService();
    _initFromGps();
  }

  @override
  void dispose() {
    _reverseDebounceTimer?.cancel();
    _searchController.dispose();
    if (widget.geocodingService == null) {
      _geocodingService.close();
    }
    super.dispose();
  }

  void _initFromGps() async {
    setState(() => _isLocating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _gpsFailed(
            'Location services are off. Showing a default area — tap the map to set your farm.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _gpsFailed(
            'Location permission denied. Showing a default area — tap the map to set your farm.');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _gpsFailed(
            'Location permission is permanently denied. Enable it in Settings, or tap the map to set your farm.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _markerPosition = LatLng(position.latitude, position.longitude);
        _isLocating = false;
        _gpsNotice = null;
      });
      _mapController.move(_markerPosition, _initialZoom);
      _scheduleReverseGeocode();
    } catch (_) {
      _gpsFailed(
          'Could not get your GPS location. Showing a default area — tap the map to set your farm.');
    }
  }

  void _gpsFailed(String message) {
    if (!mounted) return;
    setState(() {
      _isLocating = false;
      _gpsNotice = message;
    });
  }

  void _onMapTapped(TapPosition _, LatLng point) {
    setState(() {
      _markerPosition = point;
      _errorMessage = null;
    });
    _scheduleReverseGeocode();
  }

  void _onMarkerDragStart(DragStartDetails details) {
    setState(() => _draggingMarker = true);
  }

  void _onMarkerDragUpdate(DragUpdateDetails details) {
    // The map is locked while dragging, so the camera is static and the
    // screen→lat/lng roundtrip stays linear for the drag delta.
    final camera = _mapController.camera;
    final currentScreen = camera.latLngToScreenOffset(_markerPosition);
    final newScreen = currentScreen + details.delta;
    setState(() {
      _markerPosition = camera.screenOffsetToLatLng(newScreen);
      _errorMessage = null;
    });
    // Cancel any pending lookup so we never fire mid-drag.
    _reverseDebounceTimer?.cancel();
    if (_isReverseGeocoding) {
      setState(() => _isReverseGeocoding = false);
    }
  }

  void _onMarkerDragEnd(DragEndDetails details) {
    setState(() => _draggingMarker = false);
    _scheduleReverseGeocode();
  }

  /// Debounced reverse-geocode: waits `_reverseDebounce` after the last pin
  /// change before hitting Nominatim.
  void _scheduleReverseGeocode() {
    _reverseDebounceTimer?.cancel();
    _reverseDebounceTimer = Timer(_reverseDebounce, _reverseGeocode);
  }

  void _reverseGeocode() async {
    final point = _markerPosition;
    if (_isReverseGeocoding) return;
    setState(() => _isReverseGeocoding = true);

    // Best-effort: any failure leaves _address null and the screen falls back
    // to the raw coordinates. Never blocks the wizard.
    final address = await _geocodingService.reverseGeocode(point);

    if (!mounted || point != _markerPosition) return;
    setState(() {
      _address = address;
      _isReverseGeocoding = false;
    });
  }

  void _movePin(LatLng point, {bool recenterMap = true}) {
    setState(() {
      _markerPosition = point;
      _errorMessage = null;
      _searchResults = null;
      _searchError = null;
    });
    if (recenterMap) {
      _mapController.move(point, _initialZoom);
    }
    _scheduleReverseGeocode();
  }

  Future<void> _submitSearch(String raw) async {
    final query = raw.trim();
    if (query.isEmpty || _isSearching) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchResults = null;
    });

    final results = await _geocodingService.search(query);
    if (!mounted) return;

    setState(() => _isSearching = false);

    if (results.isEmpty) {
      setState(() {
        _searchError =
            'No results for "$query". Try a different barangay or area name, '
                'or place the pin by tapping the map.';
      });
      return;
    }

    // One clearly-best match → jump straight there. Multiple plausible matches
    // → let the farmer pick.
    if (results.length == 1) {
      final place = results.first;
      setState(() {
        _searchResults = null;
        _searchError = null;
        _markerPosition = LatLng(place.latitude, place.longitude);
      });
      _mapController.move(_markerPosition, _initialZoom);
      _scheduleReverseGeocode();
      return;
    }

    setState(() => _searchResults = results);
  }

  void _selectSearchResult(GeocodePlace place) {
    _movePin(LatLng(place.latitude, place.longitude));
  }

  Future<void> _confirm() async {
    if (_isSubmitting) return;

    widget.farmSetupData.latitude = _markerPosition.latitude;
    widget.farmSetupData.longitude = _markerPosition.longitude;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _submitError = null;
    });

    final result = await FarmService.createFarm(widget.farmSetupData);

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FarmSetupCompleteScreen(
            farmSetupData: widget.farmSetupData,
            frmStatus: result['frm_status'] as String? ?? 'APPROVED',
            farmId: result['farmId'] as String?,
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = false;
      _submitError = result['message'] as String? ?? 'Something went wrong.';
    });
  }

  int get _interactionFlags {
    // Disable map drag/rotate while the marker itself is being dragged so the
    // marker gestures win cleanly; keep the rest of the interactions on.
    if (_draggingMarker) {
      return InteractiveFlag.pinchZoom |
          InteractiveFlag.doubleTapZoom |
          InteractiveFlag.flingAnimation;
    }
    return InteractiveFlag.all;
  }

  /// The primary line of the location card: a readable address when we have
  /// one (or are looking one up), otherwise the raw coordinates.
  String get _locationSummary {
    if (_address != null) return _address!;
    if (_isReverseGeocoding) return 'Looking up the area…';
    return _coordinatesLabel;
  }

  String get _coordinatesLabel =>
      '${_markerPosition.latitude.toStringAsFixed(6)}, '
      '${_markerPosition.longitude.toStringAsFixed(6)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SetupHeader(
              title: 'Pin Your Farm',
              subtitle: 'Search, tap the map, or drag the pin to set the location',
            ),
            const StepProgress(
              step: 3,
              totalSteps: 3,
              label: 'Location',
              percent: 0.95,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _fallbackCenter,
                                  initialZoom: _initialZoom,
                                  onTap: _onMapTapped,
                                  interactionOptions: InteractionOptions(
                                    flags: _interactionFlags,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName:
                                        'com.example.farmspot_app',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: _markerPosition,
                                        width: 44,
                                        height: 44,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onPanStart: _onMarkerDragStart,
                                          onPanUpdate: _onMarkerDragUpdate,
                                          onPanEnd: _onMarkerDragEnd,
                                          child: const Icon(
                                            Icons.location_pin,
                                            color: Colors.redAccent,
                                            size: 44,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (_isLocating)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black26,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            if (_gpsNotice != null)
                              Positioned(
                                left: 10,
                                right: 10,
                                top: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                        alpha: 0.94),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.gps_off,
                                        color: Colors.orange,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _gpsNotice!,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Search overlay on top of the map.
                            Positioned(
                              left: 10,
                              right: 10,
                              top: 10,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  _buildSearchField(),
                                  if (_searchError != null)
                                    _searchFeedback(_searchError!),
                                  if (_searchResults != null &&
                                      _searchResults!.isNotEmpty)
                                    _buildSearchResults(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: AppColors.primaryGreen,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected location',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  _locationSummary,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _coordinatesLabel,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.black54,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            'Tap / drag the pin',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_submitError != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _submitError!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _confirm,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryGreen,
                                ),
                              )
                            : const Icon(Icons.check),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.primaryGreen,
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        label: Text(
                          _isSubmitting
                              ? 'Creating your farm...'
                              : 'Create My Farm',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Step 3 of 3',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.black38),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: _submitSearch,
        decoration: InputDecoration(
          hintText: 'Search for your barangay or area',
          prefixIcon: const Icon(Icons.search, color: Colors.black45, size: 20),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  tooltip: 'Search',
                  onPressed: () => _submitSearch(_searchController.text),
                ),
        ),
      ),
    );
  }

  Widget _searchFeedback(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _searchResults!;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final place in results)
            InkWell(
              onTap: () => _selectSearchResult(place),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: AppColors.primaryGreen,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        place.shortName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              'Tap a result to place the pin there',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }
}