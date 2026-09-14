import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/farm_profile.dart';
import '../models/listing.dart';
import '../services/farm_service.dart';
import '../services/listing_service.dart';
import '../services/routing_service.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';

/// Cebu City — the buyer position used whenever GPS is unavailable or denied.
/// Never throws: any geolocator failure falls back to this center so routing
/// can still run (the route just starts from the default area).
Future<LatLng> _defaultPosition() async {
  try {
    await GeolocatorPlatform.instance.isLocationServiceEnabled();
    if (await GeolocatorPlatform.instance.checkPermission() ==
        LocationPermission.deniedForever) {
      return const LatLng(10.3178, 123.8742);
    }
    final pos = await GeolocatorPlatform.instance.getCurrentPosition();
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return const LatLng(10.3178, 123.8742);
  }
}

Stream<LatLng> _defaultPositionStream() {
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).map((pos) => LatLng(pos.latitude, pos.longitude));
}

Future<void> _defaultContactAction({
  required String number,
  required String method,
}) async {
  final uri = Uri(scheme: method == 'SMS' ? 'sms' : 'tel', path: number);
  try {
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  } catch (_) {}
}

/// Three-step navigation flow when a buyer taps "Directions" on a farm:
/// pre-navigation summary with real car + walking routes -> live journey with
/// position updates, real remaining distance/ETA and turn-by-turn instructions
/// -> arrived / pickup confirmation with the real crop, farmer and contact.
///
/// Everything data-producing is injectable for tests; the real defaults hit
/// geolocator, the Farmspot backend and the public OSRM routers. Every failure
/// degrades to a friendly message or the Cebu City fallback — never a crash.
class FarmDirectionsScreen extends StatefulWidget {
  final String farmId;

  /// Real coordinate/name overrides the caller already holds (e.g. the map's
  /// [FarmPin]); the screen falls back to fetching the farm profile itself.
  final LatLng? farmPosition;
  final String? farmName;

  /// Set when navigation started from a listing, so the arrived step shows the
  /// real crop the buyer is picking up.
  final String? listingId;

  final Future<LatLng> Function() loadPosition;
  final Future<FarmProfileData> Function(String farmId) loadFarmProfile;
  final Future<Listing> Function(String listingId) loadListing;
  final Stream<LatLng> Function() positionStream;
  final RoutingService? routing;
  final Future<void> Function({
    required String listingId,
    required String method,
  })?
  contactLogger;
  final Future<void> Function({required String number, required String method})?
  contactAction;

  const FarmDirectionsScreen({
    super.key,
    required this.farmId,
    this.farmPosition,
    this.farmName,
    this.listingId,
    this.loadPosition = _defaultPosition,
    this.loadFarmProfile = FarmService.fetchFarmProfile,
    this.loadListing = ListingService.fetchListing,
    this.positionStream = _defaultPositionStream,
    this.routing,
    this.contactLogger,
    this.contactAction,
  });

  @override
  State<FarmDirectionsScreen> createState() => _FarmDirectionsScreenState();
}

enum _Step { direction, journey, arrived }

class _FarmDirectionsScreenState extends State<FarmDirectionsScreen> {
  static const LatLng _fallback = LatLng(10.3178, 123.8742);
  static final Distance _distance = const Distance();

  final MapController _mapController = MapController();

  _Step _step = _Step.direction;
  String _mode = 'foot';

  LatLng _current = _fallback;
  LatLng? _farmPos;
  String _farmName = '';
  FarmProfileData? _profile;
  Listing? _listing;

  RoutePlan? _footPlan;
  RoutePlan? _carPlan;
  bool _loading = true;
  String? _error;

  StreamSubscription<LatLng>? _positionSub;
  bool _liveAvailable = true;
  LatLng _live = _fallback;
  int _nextStepIndex = 0;
  List<double>? _cumulative;
  double? _cachedRemaining;

  late final RoutingService _routing;
  late final Future<void> Function({
    required String listingId,
    required String method,
  })
  _contactLogger;
  late final Future<void> Function({
    required String number,
    required String method,
  })
  _contactAction;

  @override
  void initState() {
    super.initState();
    _routing = widget.routing ?? RoutingService();
    _contactLogger = widget.contactLogger ?? ListingService.logContact;
    _contactAction = widget.contactAction ?? _defaultContactAction;
    _initialize();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    if (widget.routing == null) _routing.close();
    super.dispose();
  }

  RoutePlan? get _plan => _mode == 'foot' ? _footPlan : _carPlan;

  bool _initializing = false;

  Future<void> _initialize() async {
    if (_initializing) return;
    _initializing = true;
    _loading = true;
    _error = null;

    LatLng current = _fallback;
    try {
      current = await widget.loadPosition();
    } catch (_) {}
    _current = current;

    var farmPos = widget.farmPosition;
    var farmName = widget.farmName ?? '';

    try {
      final profile = await widget.loadFarmProfile(widget.farmId);
      if (!mounted) return;
      _profile = profile;
      if (farmName.isEmpty) farmName = profile.name;
      if (farmPos == null &&
          profile.latitude != null &&
          profile.longitude != null) {
        farmPos = LatLng(profile.latitude!, profile.longitude!);
      }
    } catch (_) {}

    final listingId = widget.listingId;
    if (listingId != null && listingId.isNotEmpty) {
      try {
        _listing = await widget.loadListing(listingId);
      } catch (_) {}
    }

    if (!mounted) return;
    if (farmPos == null) {
      setState(() {
        _initializing = false;
        _loading = false;
        _error =
            'This farm has no location set yet. View its crops from the Farm '
            'Profile instead.';
      });
      return;
    }
    _farmPos = farmPos;
    _farmName = farmName.isEmpty ? 'Farm' : farmName;

    final results = await Future.wait([
      _routing.getRoute(from: _current, to: farmPos, profile: 'foot'),
      _routing.getRoute(from: _current, to: farmPos, profile: 'car'),
    ]);
    if (!mounted) return;

    final foot = results[0];
    final car = results[1];
    if (foot == null && car == null) {
      setState(() {
        _initializing = false;
        _loading = false;
        _error =
            'Could not calculate a route. Check your internet connection '
            'and try again.';
      });
      return;
    }

    setState(() {
      _initializing = false;
      _footPlan = foot;
      _carPlan = car;
      _loading = false;
    });
  }

  void _startJourney() {
    _live = _current;
    _liveAvailable = true;
    _cachedRemaining = null;
    final plan = _plan;
    _nextStepIndex = _firstUpcomingStep(plan);
    _cumulative = _buildCumulative(plan);
    setState(() => _step = _Step.journey);
    _positionSub = widget.positionStream().listen(
      _onLiveFix,
      onError: (Object _) {
        if (!mounted) return;
        setState(() => _liveAvailable = false);
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _liveAvailable = false);
      },
    );
  }

  void _endJourney() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  int _firstUpcomingStep(RoutePlan? plan) {
    if (plan == null || plan.steps.isEmpty) return 0;
    var idx = plan.steps.length > 1 ? 1 : 0;
    while (idx < plan.steps.length - 1) {
      final p = plan.steps[idx].position;
      if (p == null) {
        idx++;
        continue;
      }
      if (_distance(_live, p) <= _arriveThreshold) {
        idx++;
        continue;
      }
      break;
    }
    return idx;
  }

  double get _arriveThreshold => _mode == 'foot' ? 25 : 45;

  List<double> _buildCumulative(RoutePlan? plan) {
    final geometry = plan?.geometry ?? const <LatLng>[];
    final cumulative = List<double>.filled(geometry.length, 0);
    for (var i = 1; i < geometry.length; i++) {
      cumulative[i] =
          cumulative[i - 1] + _distance(geometry[i - 1], geometry[i]);
    }
    return cumulative;
  }

  void _onLiveFix(LatLng pos) {
    if (!mounted) return;
    setState(() {
      _live = pos;
      _liveAvailable = true;
      _cachedRemaining = null;
    });
    _advanceInstructions(pos);
    try {
      _mapController.move(pos, 16);
    } catch (_) {}
  }

  void _advanceInstructions(LatLng pos) {
    final plan = _plan;
    if (plan == null || plan.steps.isEmpty) return;
    final threshold = _arriveThreshold;
    while (_nextStepIndex < plan.steps.length - 1) {
      final p = plan.steps[_nextStepIndex].position;
      if (p == null) {
        _nextStepIndex++;
        continue;
      }
      if (_distance(pos, p) <= threshold) {
        _nextStepIndex++;
        continue;
      }
      break;
    }
  }

  double? get _remainingDistance {
    if (_cachedRemaining != null) return _cachedRemaining;
    final plan = _plan;
    if (plan == null || plan.geometry.isEmpty) return null;
    final cumulative = _cumulative ?? _buildCumulative(plan);
    final geometry = plan.geometry;
    var nearest = 0;
    var best = _distance(_live, geometry.first);
    for (var i = 1; i < geometry.length; i++) {
      final d = _distance(_live, geometry[i]);
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    final cumulativeTotal = cumulative.isEmpty
        ? 0.0
        : cumulative.last - cumulative[nearest];
    final remaining = best + cumulativeTotal;
    _cachedRemaining = remaining;
    return remaining;
  }

  Duration? get _remainingEta {
    final plan = _plan;
    final remaining = _remainingDistance;
    if (plan == null || remaining == null || plan.distanceMeters <= 0) {
      return null;
    }
    final secondsPerMeter = plan.durationSeconds / plan.distanceMeters;
    return Duration(seconds: (remaining * secondsPerMeter).round());
  }

  String get _bannerInstruction {
    final plan = _plan;
    if (plan == null || plan.steps.isEmpty) return 'Head to the farm';
    final idx = _nextStepIndex >= plan.steps.length
        ? plan.steps.length - 1
        : _nextStepIndex;
    return plan.steps[idx].instruction;
  }

  String get _bannerSub {
    final plan = _plan;
    if (plan == null || plan.steps.isEmpty) return '';
    final idx = _nextStepIndex >= plan.steps.length
        ? plan.steps.length - 1
        : _nextStepIndex;
    final position = plan.steps[idx].position;
    final farm = _farmPos;
    if (idx >= plan.steps.length - 1) {
      final ahead = farm == null ? 0.0 : _distance(_live, farm);
      return 'Farm is ${_formatDistance(ahead)} ahead';
    }
    if (position == null) return '';
    return 'Turn in ${_formatDistance(_distance(_live, position))}';
  }

  CropListing? get _pickup {
    if (_listing != null) return _listing!.toCropListing();
    for (final listing in _profile?.listings ?? const <CropListing>[]) {
      if (listing.status == 'AVAILABLE_NOW') return listing;
    }
    final listings = _profile?.listings ?? const <CropListing>[];
    return listings.isNotEmpty ? listings.first : null;
  }

  String get _pickupCrop => _pickup?.cropName ?? _farmName;

  String get _pickupStatusLabel =>
      _statusLabel(_pickup?.status ?? 'NOT_AVAILABLE');

  String get _farmerName =>
      _listing?.farmerName ??
      (_pickup?.farmName.isNotEmpty ?? false ? _pickup!.farmName : _farmName);

  String get _contactNumber {
    final number = _pickup?.contactNumber ?? '';
    if (number.trim().isEmpty || number == 'N/A') return '';
    return number;
  }

  String? get _contactListingId =>
      _pickup?.listingId?.isNotEmpty ?? false ? _pickup!.listingId : null;

  String get _subtitle =>
      '$_farmName · ${_profile?.barangay ?? 'farm location'}';

  Future<void> _launchContact(String method) async {
    final number = _contactNumber;
    if (number.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No contact number is linked to this farm yet.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    final listingId = _contactListingId;
    if (listingId != null) {
      unawaited(_contactLogger(listingId: listingId, method: method));
    }
    await _contactAction(number: number, method: method);
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.direction:
        return _buildDirection();
      case _Step.journey:
        return _buildJourney();
      case _Step.arrived:
        return _buildArrived();
    }
  }

  Widget _buildDirection() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'Direction',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            SizedBox(height: 260, child: _buildMap()),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _farmName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _profile?.barangay ?? 'farm location',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      _BuildError(error: _error!, onRetry: _initialize)
                    else ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ModePill(
                              label: _planLabel(_footPlan),
                              sub: _planSub(_footPlan, 'walking'),
                              selected: _mode == 'foot',
                              enabled: _footPlan != null,
                              onTap: _footPlan == null
                                  ? null
                                  : () => setState(() => _mode = 'foot'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ModePill(
                              label: _planLabel(_carPlan),
                              sub: _planSub(_carPlan, 'riding'),
                              selected: _mode == 'car',
                              enabled: _carPlan != null,
                              onTap: _carPlan == null
                                  ? null
                                  : () => setState(() => _mode = 'car'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _plan == null ? null : _startJourney,
                          icon: const Icon(Icons.navigation),
                          label: const Text('Start Navigation'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'location calculation',
                        style: TextStyle(fontSize: 11, color: Colors.black38),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _planLabel(RoutePlan? plan) =>
      plan == null ? '—' : _formatDuration(plan.durationSeconds);

  String _planSub(RoutePlan? plan, String modeLabel) => plan == null
      ? modeLabel
      : '${_formatDistance(plan.distanceMeters)} · $modeLabel';

  Widget _buildMap() {
    final plan = _plan;
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _current, initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.farmspot_app',
              ),
              if (plan != null && plan.geometry.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: plan.geometry,
                      strokeWidth: 5,
                      color: AppColors.primaryGreen,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_step == _Step.journey)
                    _userMarker(_live)
                  else
                    _userMarker(_current),
                  if (_farmPos != null) _destinationMarker(_farmPos!),
                ],
              ),
            ],
          ),
        ),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black26,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
        if (_step == _Step.journey)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _instructionBanner(
              main: _bannerInstruction,
              sub: _bannerSub,
            ),
          ),
      ],
    );
  }

  Marker _userMarker(LatLng point) {
    return Marker(
      width: 30,
      height: 30,
      point: point,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.blue, width: 2),
        ),
        child: const Icon(Icons.navigation, color: Colors.blue, size: 18),
      ),
    );
  }

  Marker _destinationMarker(LatLng point) {
    return Marker(
      width: 34,
      height: 34,
      point: point,
      child: const Icon(
        Icons.location_on,
        color: AppColors.primaryGreen,
        size: 34,
      ),
    );
  }

  Widget _instructionBanner({required String main, required String sub}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.navigation, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  main,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (!_liveAvailable)
            const Icon(Icons.gps_off, color: Colors.orange, size: 18),
        ],
      ),
    );
  }

  Widget _buildJourney() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMap()),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _JourneyStat(
                        value: _remainingEta == null
                            ? '—'
                            : _formatDuration(
                                _remainingEta!.inSeconds.toDouble(),
                              ),
                        label: 'ETA',
                      ),
                      _JourneyStat(
                        value: _remainingDistance == null
                            ? '—'
                            : _formatDistance(_remainingDistance!),
                        label: 'Remaining',
                      ),
                      _JourneyStat(
                        value: _mode == 'foot' ? 'Walking' : 'Riding',
                        label: '',
                      ),
                    ],
                  ),
                  if (!_liveAvailable) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Live updates unavailable — GPS permission or location '
                      'services are off. Use “Mark as Arrived” when you reach '
                      'the farm.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _endJourney();
                        setState(() => _step = _Step.arrived);
                      },
                      icon: const Icon(Icons.location_on),
                      label: const Text('Mark as Arrived'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () {
                      _endJourney();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    label: const Text(
                      'Cancel Navigation',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrived() {
    final canContact = _contactNumber.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.primaryGreen,
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: const Column(
                children: [
                  Icon(Icons.celebration, color: Colors.white, size: 44),
                  SizedBox(height: 10),
                  Text(
                    "You've Arrived!",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _subtitle,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const Text(
                    "YOU'RE HERE TO PICKUP",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.green.shade50,
                          child: const Icon(Icons.eco, color: Colors.green),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pickupCrop,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _pickupStatusLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'CONTACT FARMERS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (canContact)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primaryGreen),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _farmerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                                Text(
                                  _contactNumber,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _circleIconButton(
                            icon: Icons.phone,
                            tooltip: 'Call farmer',
                            onPressed: () => _launchContact('CALL'),
                          ),
                          const SizedBox(width: 8),
                          _circleIconButton(
                            icon: Icons.chat_bubble_outline,
                            tooltip: 'Send SMS',
                            onPressed: () => _launchContact('SMS'),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'No contact number is linked to this farm yet.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Browse'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.primaryGreen,
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'AVAILABLE_NOW':
        return 'Available Now';
      case 'SOON_TO_HARVEST':
        return 'Soon to Harvest';
      default:
        return 'Not Available';
    }
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final String sub;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _ModePill({
    required this.label,
    required this.sub,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryGreen.withValues(alpha: 0.12)
              : const Color(0xFFEAF6EC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primaryGreen
                : AppColors.primaryGreen.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: enabled ? Colors.black87 : Colors.black26,
              ),
            ),
            Text(
              sub,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? Colors.black54 : Colors.black26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyStat extends StatelessWidget {
  final String value;
  final String label;

  const _JourneyStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        if (label.isNotEmpty)
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
      ],
    );
  }
}

class _BuildError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _BuildError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.cloud_off, color: Colors.black38, size: 32),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              side: const BorderSide(color: AppColors.primaryGreen),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours hr' : '$hours hr $rest min';
}

String _formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  if (km >= 10) return '${km.round()} km';
  return '${km.toStringAsFixed(1)} km';
}
