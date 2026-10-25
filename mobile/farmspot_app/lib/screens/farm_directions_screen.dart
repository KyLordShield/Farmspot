import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/farm_profile.dart';
import '../models/listing.dart';
import '../services/farm_service.dart';
import '../services/listing_service.dart';
import '../services/message_service.dart';
import '../services/routing_service.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import '../widgets/map_tile_layer.dart';
import 'in_app_messages_screen.dart';

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
  /// The farm to navigate to. Null when the destination is an ad-hoc pin — a
  /// location a seller shared in chat — in which case [farmPosition] is the
  /// only source of the destination and no farm profile is fetched.
  final String? farmId;

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

  /// In-app messaging for the arrived screen's "Message" button, so it opens the
  /// same real buyer <-> seller thread as the product detail screen. Injectable
  /// for tests; defaults to the real backend service.
  final MessagesGateway? messagesGateway;

  /// When true, "Start Navigation" feeds fake positions along the route
  /// geometry instead of real GPS — useful for quick visual demos on the
  /// phone without walking around. Only shown in debug builds.
  final bool simulate;

  const FarmDirectionsScreen({
    super.key,
    this.farmId,
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
    this.messagesGateway,
    this.simulate = false,
  });

  @override
  State<FarmDirectionsScreen> createState() => _FarmDirectionsScreenState();
}

enum _Step { direction, journey, arrived }

class _FarmDirectionsScreenState extends State<FarmDirectionsScreen>
    with SingleTickerProviderStateMixin {
  static const LatLng _fallback = LatLng(10.3178, 123.8742);
  static final Distance _distance = const Distance();

  /// How far off the planned polyline counts as "off route". Tight enough to
  /// catch a wrong turn, loose enough to ignore normal GPS drift.
  double get _offRouteThreshold => _mode == 'foot' ? 30 : 45;

  /// A miss this many times the threshold cannot be GPS drift: reroute on the
  /// first fix instead of waiting for a second confirmation.
  static const double _offRouteSnapFactor = 1.75;

  /// Consecutive off-route fixes required before asking the router again, so a
  /// single bad GPS reading cannot trigger a reroute.
  static const int _offRouteFixesBeforeReroute = 2;

  /// Minimum gap between reroute requests, protecting the public OSRM router
  /// (and avoiding request loops while the GPS settles). Short enough that a
  /// second wrong turn does not leave the traveller on a stale line.
  static const Duration _rerouteCooldown = Duration(seconds: 4);

  /// Within this distance of the farm, rerouting adds no value.
  static const double _nearDestinationMeters = 70;

  final MapController _mapController = MapController();

  _Step _step = _Step.direction;
  String _mode = 'foot';

  LatLng _current = _fallback;
  LatLng? _farmPos;
  String _farmName = '';
  FarmProfileData? _profile;
  Listing? _listing;

  /// True while the arrived screen is opening the seller conversation, so the
  /// Message button can show progress instead of firing twice.
  bool _startingThread = false;

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

  /// Rerouting state: true while a replacement route is being fetched, and the
  /// guards that debounce off-route fixes and requests.
  bool _isRerouting = false;
  bool _rerouteInFlight = false;
  int _offRouteStreak = 0;
  DateTime? _lastRerouteAt;

  /// Debug-only manual GPS: real GPS is detached and the traveller position is
  /// driven by dragging the map pin or holding the on-screen arrow pad.
  bool _manualGps = false;
  Timer? _dpadTimer;
  static const double _manualStepMeters = 10;
  static const double _manualDragMinMeters = 5;

  /// Current travel bearing in degrees (0 = north, 90 = east, clockwise).
  /// Updates as the journey advances so the map can swing to a Google-Maps
  /// style heading-up view (the direction you're traveling points "up").
  ///
  /// The value eases toward [_headingTarget] via [_headingController] so real
  /// GPS turns sweep instead of snapping.
  double _heading = 0;
  double _headingTarget = 0;
  double _headingFrom = 0;
  double _headingDelta = 0;

  /// Animates the camera swing between the current heading and the target.
  /// Duration is scaled by turn size so small jitters turn gently and big
  /// road turns still feel prompt.
  late final AnimationController _headingController;

  double get _headingTurnSize => _headingDelta.abs();

  /// Twists the map so the direction of travel points up. Runs even while
  /// standing still: the camera stays facing the road the user is on instead
  /// of whatever direction the last GPS dance happened to point.
  void _turnToward(double target) {
    if (target == _headingTarget && _headingController.isAnimating) return;
    _headingTarget = target;
    _headingFrom = _heading;
    _headingDelta = _shortestWay(_headingTarget - _headingFrom);
    final turn = _headingTurnSize;
    // Sub-degree tweaks are noise; snap instead of replaying an animation.
    if (turn.abs() < 1) {
      _heading = _headingTarget;
      _applyHeading();
      return;
    }
    // Quick-start ease: the camera moves right away and settles as it arrives
    // at the new heading, so it tracks the turn instead of trailing it.
    final ms = (240 + turn * 1.2).clamp(320, 550).toInt();
    _headingController.duration = Duration(milliseconds: ms);
    _headingController.forward(from: 0);
  }

  /// Wraps an angular difference into (-180, 180] so east->west interpolates
  /// the short way across 0° instead of spinning 350° the long way around.
  double _shortestWay(double delta) {
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return delta;
  }

  void _applyHeading() {
    if (!mounted || _manualGps) return;
    final t = _headingController.value;
    final curve = Curves.easeOutCubic.transform(t);
    _heading = _headingFrom + _headingDelta * curve;
    try {
      _mapController.moveAndRotate(_live, 16, -_heading);
    } catch (_) {}
  }

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

  /// Debug-only: when true, the position stream is replaced by a fake
  /// replay of the route geometry so you can demo the journey at your desk
  /// without holding a phone outside.
  bool _simulateOn = false;

  @override
  void initState() {
    super.initState();
    _routing = widget.routing ?? RoutingService();
    _contactLogger = widget.contactLogger ?? ListingService.logContact;
    _contactAction = widget.contactAction ?? _defaultContactAction;
    _simulateOn = widget.simulate;
    _headingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(_applyHeading);
    _initialize();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _simTimer?.cancel();
    _dpadTimer?.cancel();
    _headingController.dispose();
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

    // A shared pin has no farm record behind it, so there is nothing to fetch.
    // Skipping the call also keeps a stale/unknown id from turning a perfectly
    // good coordinate into an error.
    final farmId = widget.farmId;
    if (farmId != null && farmId.isNotEmpty) {
      try {
        final profile = await widget.loadFarmProfile(farmId);
        if (!mounted) return;
        _profile = profile;
        if (farmName.isEmpty) farmName = profile.name;
        if (farmPos == null &&
            profile.latitude != null &&
            profile.longitude != null) {
          farmPos = LatLng(profile.latitude!, profile.longitude!);
        }
      } catch (_) {}
    }

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
    _farmName = farmName.isEmpty
        ? (farmId == null ? 'Shared location' : 'Farm')
        : farmName;

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

    // The map starts at the traveller's position. Without this the destination
    // can sit far outside the viewport, which reads as "the farm is here" even
    // though the route is correct. Fit both ends once the route is known.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitRouteBounds();
    });
  }

  void _fitRouteBounds() {
    final destination = _farmPos;
    if (destination == null) return;

    final points = <LatLng>[_current, destination, ...?_plan?.geometry];
    if (points.length < 2) return;

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(36, 36, 36, 36),
        ),
      );
    } catch (_) {
      // The map may not be mounted yet; the initial centre is still usable.
    }
  }

  void _startJourney() {
    _live = _current;
    _heading = 0;
    _liveAvailable = true;
    _cachedRemaining = null;
    _offRouteStreak = 0;
    _rerouteInFlight = false;
    _isRerouting = false;
    _lastRerouteAt = null;
    final plan = _plan;
    _nextStepIndex = _firstUpcomingStep(plan);
    _cumulative = _buildCumulative(plan);
    setState(() => _step = _Step.journey);
    // Enter the same zoomed, traveller-centred view the simulation uses instead
    // of staying on the zoomed-out overview until the first GPS fix arrives.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == _Step.journey) _applyHeading();
    });

    if (_simulateOn) {
      _startSimulation(plan);
      return;
    }
    _listenToLivePosition();
  }

  /// (Re)subscribes to real GPS. Used at journey start and when leaving the
  /// debug manual-GPS mode.
  void _listenToLivePosition() {
    _positionSub?.cancel();
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

  Timer? _simTimer;
  List<LatLng> _simPath = const [];
  int _simIndex = 0;

  /// Replays the route as a smooth fake-journey. The stream version jumped
  /// vertex-to-vertex, which looked like blinking and skipped past the narrow
  /// 25m turn-advancement window — so the banner never changed. This walks the
  /// path in ~8-meter interpolated hops (well inside the turn threshold) with
  /// a short timer, landing on the farm when done.
  void _startSimulation(RoutePlan? plan) {
    final geometry = plan?.geometry ?? const <LatLng>[];
    _simPath = _buildSimulationPath(geometry);
    if (_simPath.length < 2) {
      if (!mounted) return;
      setState(() => _liveAvailable = false);
      return;
    }
    _simIndex = 0;
    const totalMs = 25000; // entire demo finishes in ~25s
    final tickMs = (totalMs / (_simPath.length - 1)).round().clamp(50, 400);
    _simTimer = Timer.periodic(Duration(milliseconds: tickMs), (_) {
      if (!mounted) {
        _simTimer?.cancel();
        return;
      }
      if (_simIndex >= _simPath.length) {
        _simTimer?.cancel();
        return;
      }
      final pos = _simPath[_simIndex];
      _simIndex++;
      _onLiveFix(pos);
    });
  }

  /// Builds a dense sequence of positions spaced ~8m apart along the route
  /// geometry so the marker glides and each turn point is crossed inside the
  /// foot (25m) / car (45m) arrival threshold, advancing the banner.
  List<LatLng> _buildSimulationPath(List<LatLng> geometry) {
    if (geometry.length < 2) return List.of(geometry);
    final cumulative = _buildCumulative(
      RoutePlan(
        distanceMeters: 0,
        durationSeconds: 0,
        geometry: geometry,
        steps: const [],
      ),
    );
    final total = cumulative.isEmpty ? 0.0 : cumulative.last;
    if (total <= 0) return List.of(geometry);
    const hop = 8.0; // meters between simulated fixes
    final samples = (total / hop).ceil().clamp(4, 600);
    final path = <LatLng>[];
    for (var i = 0; i <= samples; i++) {
      path.add(_pointAlong(geometry, cumulative, total * i / samples));
    }
    return path;
  }

  /// Returns the point exactly [targetMeters] along a polyline.
  LatLng _pointAlong(
    List<LatLng> geometry,
    List<double> cumulative,
    double targetMeters,
  ) {
    if (geometry.length == 1) return geometry.first;
    final length = cumulative.isEmpty ? 0.0 : cumulative.last;
    if (length <= 0) return geometry.first;
    final target = targetMeters.clamp(0.0, length);
    for (var i = 1; i < geometry.length; i++) {
      if (cumulative[i] >= target) {
        final seg = cumulative[i] - cumulative[i - 1];
        if (seg <= 0) return geometry[i - 1];
        final frac = (target - cumulative[i - 1]) / seg;
        final a = geometry[i - 1];
        final b = geometry[i];
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * frac,
          a.longitude + (b.longitude - a.longitude) * frac,
        );
      }
    }
    return geometry.last;
  }

  void _endJourney() {
    _positionSub?.cancel();
    _positionSub = null;
    _simTimer?.cancel();
    _simTimer = null;
    _dpadTimer?.cancel();
    _dpadTimer = null;
    _rerouteInFlight = false;
    _isRerouting = false;
    _offRouteStreak = 0;
    _manualGps = false;
  }

  int _firstUpcomingStep(RoutePlan? plan, [LatLng? origin]) {
    if (plan == null || plan.steps.isEmpty) return 0;
    final from = origin ?? _live;
    var idx = plan.steps.length > 1 ? 1 : 0;
    while (idx < plan.steps.length - 1) {
      final p = plan.steps[idx].position;
      if (p == null) {
        idx++;
        continue;
      }
      if (_distance(from, p) <= _arriveThreshold) {
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
    final from = _live;
    setState(() {
      _live = pos;
      _liveAvailable = true;
      _cachedRemaining = null;
    });
    _advanceInstructions(pos);
    if (!_simulateOn) unawaited(_maybeReroute(pos));
    // Steer by actual movement direction (this fix -> last fix), so the
    // camera turns exactly when the user turns — no route look-ahead (which
    // rotated early) and no long trailing ease (which lagged the turn). The
    // distance gate keeps standing-still GPS jitter from spinning the map,
    // even though the rotation itself eases smoothly.
    if (!_manualGps) {
      if (_simulateOn || _distance(from, pos) > 2) {
        _turnToward(_bearingFrom(from, pos));
      }
      // Recentre on every fix, even when the heading did not change: walking
      // a straight road must still scroll the map with the traveller.
      _applyHeading();
    }
  }

  /// Clockwise bearing (0..360) traveling from [a] to [b] in degrees.
  double _bearingFrom(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
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

  /// Debug-only: detaches real GPS and lets the traveller position be driven
  /// manually (drag the pin, or hold the arrow pad) so off-route detection and
  /// rerouting can be exercised indoors.
  void _enterManualGps() {
    if (!kDebugMode || _step != _Step.journey) return;
    _positionSub?.cancel();
    _positionSub = null;
    _simTimer?.cancel();
    _simTimer = null;
    _dpadTimer?.cancel();
    setState(() {
      _manualGps = true;
      _simulateOn = false;
      _liveAvailable = true;
    });
    try {
      _mapController.moveAndRotate(_live, _mapController.camera.zoom, 0);
    } catch (_) {}
  }

  void _exitManualGps() {
    if (!_manualGps) return;
    _dpadTimer?.cancel();
    _dpadTimer = null;
    setState(() {
      _manualGps = false;
    });
    _listenToLivePosition();
  }

  void _onManualDragUpdate(DragUpdateDetails details) {
    final camera = _mapController.camera;
    final currentScreen = camera.latLngToScreenOffset(_live);
    final newScreen = currentScreen + details.delta;
    final next = camera.screenOffsetToLatLng(newScreen);
    if (_distance(_live, next) < _manualDragMinMeters) return;
    _onLiveFix(next);
  }

  void _onManualDragEnd(DragEndDetails details) {
    try {
      _mapController.move(_live, _mapController.camera.zoom);
    } catch (_) {}
  }

  void _startManualMove(double bearing) {
    if (!_manualGps) return;
    _moveManual(bearing);
    _dpadTimer?.cancel();
    _dpadTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) => _moveManual(bearing),
    );
  }

  void _stopManualMove() {
    _dpadTimer?.cancel();
    _dpadTimer = null;
  }

  void _moveManual(double bearing) {
    if (!_manualGps || _step != _Step.journey) return;
    final next = _offsetPoint(_live, _manualStepMeters, bearing);
    _onLiveFix(next);
    try {
      _mapController.move(next, _mapController.camera.zoom);
    } catch (_) {}
  }

  /// Debug-only: walks the traveller a short distance forward from where they
  /// currently are, then steps sideways off the route — a fake wrong turn.
  ///
  /// This feeds the exact same [_onLiveFix] path real GPS uses, so the
  /// off-route detector and the real reroute request are exercised without
  /// leaving the desk. Needs SIM off; live GPS is left running, so the next
  /// real fix simply resumes normal navigation.
  Future<void> _simulateWrongTurn() async {
    if (!kDebugMode || _step != _Step.journey) return;
    if (_simulateOn) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Turn SIM off to test off-route rerouting.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    final plan = _plan;
    if (plan == null || plan.geometry.length < 2) return;

    final cumulative = _cumulative ?? _buildCumulative(plan);
    final total = cumulative.isEmpty ? 0.0 : cumulative.last;
    if (total <= 0) return;

    // Stay relative to the current position so this reads as a wrong turn from
    // here, not a teleport to an unrelated part of the route.
    final here = _nearestDistanceAlong(plan.geometry, cumulative, _live);
    final turnAt = (here + 40).clamp(0.0, total);
    final midpoint = _pointAlong(
      plan.geometry,
      cumulative,
      (here + turnAt) / 2,
    );
    final turnPoint = _pointAlong(plan.geometry, cumulative, turnAt);
    final ahead = _pointAlong(
      plan.geometry,
      cumulative,
      (turnAt + 30).clamp(0.0, total),
    );
    final heading = _bearingFrom(turnPoint, ahead);
    final offRoute = _offsetPoint(
      turnPoint,
      _offRouteThreshold + 20,
      heading + 90,
    );
    final furtherOff = _offsetPoint(offRoute, 25, heading + 90);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Debug: simulating a wrong turn from here…'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

    // Approach the turn on-route, then step off it in two fixes. The first
    // off-route fix primes the streak; the second fires the reroute.
    _onLiveFix(_live);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _step != _Step.journey) return;
    _onLiveFix(midpoint);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _step != _Step.journey) return;
    _onLiveFix(turnPoint);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _step != _Step.journey) return;
    _onLiveFix(offRoute);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _step != _Step.journey) return;
    _onLiveFix(furtherOff);
  }

  /// Cumulative distance along [geometry] of the vertex nearest to [pos].
  double _nearestDistanceAlong(
    List<LatLng> geometry,
    List<double> cumulative,
    LatLng pos,
  ) {
    if (geometry.isEmpty || cumulative.isEmpty) return 0;
    var best = double.infinity;
    var bestDistance = 0.0;
    for (var i = 0; i < geometry.length; i++) {
      final d = _distance(pos, geometry[i]);
      if (d < best) {
        best = d;
        bestDistance = cumulative[i];
      }
    }
    return bestDistance;
  }

  /// Offsets [from] by [meters] along [bearingDegrees] (0 = north, clockwise).
  LatLng _offsetPoint(LatLng from, double meters, double bearingDegrees) {
    const metersPerDegree = 111320.0;
    final radians = bearingDegrees * math.pi / 180;
    final dLat = meters * math.cos(radians) / metersPerDegree;
    final dLon =
        meters *
        math.sin(radians) /
        (metersPerDegree *
            math.cos(from.latitude * math.pi / 180).clamp(0.01, 1.0));
    return LatLng(from.latitude + dLat, from.longitude + dLon);
  }

  /// Detects a sustained departure from the planned polyline and asks the
  /// router for a fresh route from the live position, replacing the active plan
  /// so the polyline, turn list, distance and ETA all follow the new path.
  ///
  /// Deliberately debounced: one rogue GPS fix is ignored, requests are spaced
  /// by [_rerouteCooldown], and nothing happens near the destination.
  Future<void> _maybeReroute(LatLng pos) async {
    if (_step != _Step.journey) return;
    final plan = _plan;
    final destination = _farmPos;
    if (plan == null || destination == null || plan.geometry.length < 2) {
      return;
    }

    final offRouteMeters = _matchRoute(pos, plan.geometry).distance;
    if (offRouteMeters <= _offRouteThreshold) {
      _offRouteStreak = 0;
      return;
    }

    // Close to the farm, snapping to the old line is fine — don't ask again.
    if (_distance(pos, destination) <= _nearDestinationMeters) {
      _offRouteStreak = 0;
      return;
    }

    _offRouteStreak++;
    // A miss this large is a wrong turn, not drift: skip the confirmation fix
    // so the new line appears as soon as the traveller leaves the road.
    if (offRouteMeters >= _offRouteThreshold * _offRouteSnapFactor) {
      _offRouteStreak = math.max(_offRouteStreak, _offRouteFixesBeforeReroute);
    }
    if (_rerouteInFlight || _offRouteStreak < _offRouteFixesBeforeReroute) {
      return;
    }

    final now = DateTime.now();
    final last = _lastRerouteAt;
    if (last != null && now.difference(last) < _rerouteCooldown) return;

    _lastRerouteAt = now;
    _rerouteInFlight = true;
    final profile = _mode;
    if (mounted) setState(() => _isRerouting = true);

    final fresh = await _routing.getRoute(
      from: pos,
      to: destination,
      profile: profile,
    );

    _rerouteInFlight = false;
    if (!mounted || _step != _Step.journey || profile != _mode) {
      if (mounted) setState(() => _isRerouting = false);
      return;
    }

    if (fresh == null || fresh.geometry.length < 2) {
      setState(() => _isRerouting = false);
      return;
    }

    final cumulative = _buildCumulative(fresh);
    // The request may have taken a few seconds; advance turns from where the
    // traveller is now, not where they were when the request started.
    final nextStep = _firstUpcomingStep(fresh, _live);
    setState(() {
      if (profile == 'foot') {
        _footPlan = fresh;
      } else {
        _carPlan = fresh;
      }
      _cumulative = cumulative;
      _nextStepIndex = nextStep;
      _cachedRemaining = null;
      _offRouteStreak = 0;
      _isRerouting = false;
    });
  }

  /// Nearest segment of [geometry] to [pos]: its perpendicular distance, the
  /// projected point on the line, and the segment's start index. Vertex-only
  /// distance would overstate the miss on long straight legs.
  ({double distance, LatLng point, int segment}) _matchRoute(
    LatLng pos,
    List<LatLng> geometry,
  ) {
    if (geometry.isEmpty) {
      return (distance: double.infinity, point: pos, segment: 0);
    }
    if (geometry.length == 1) {
      return (
        distance: _distance(pos, geometry.first),
        point: geometry.first,
        segment: 0,
      );
    }
    var bestDistance = double.infinity;
    var bestPoint = geometry.first;
    var bestSegment = 0;
    for (var i = 1; i < geometry.length; i++) {
      final match = _projectOnSegment(pos, geometry[i - 1], geometry[i]);
      if (match.distance < bestDistance) {
        bestDistance = match.distance;
        bestPoint = match.point;
        bestSegment = i - 1;
      }
    }
    return (distance: bestDistance, point: bestPoint, segment: bestSegment);
  }

  /// Local flat-earth projection around [a]; accurate enough at the tens of
  /// meters scale this decision is made at.
  ({double distance, LatLng point}) _projectOnSegment(
    LatLng p,
    LatLng a,
    LatLng b,
  ) {
    const metersPerDegree = 111320.0;
    final cosLat = math.cos(a.latitude * math.pi / 180);
    double projectX(LatLng q) =>
        (q.longitude - a.longitude) * metersPerDegree * cosLat;
    double projectY(LatLng q) => (q.latitude - a.latitude) * metersPerDegree;

    final px = projectX(p);
    final py = projectY(p);
    final bx = projectX(b);
    final by = projectY(b);
    final lengthSquared = bx * bx + by * by;
    if (lengthSquared == 0) {
      return (distance: _distance(p, a), point: a);
    }

    final t = ((px * bx + py * by) / lengthSquared).clamp(0.0, 1.0);
    final dx = px - bx * t;
    final dy = py - by * t;
    final point = LatLng(
      a.latitude + (by * t) / metersPerDegree,
      a.longitude + (bx * t) / (metersPerDegree * cosLat),
    );
    return (distance: math.sqrt(dx * dx + dy * dy), point: point);
  }

  /// The part of the route still ahead of [pos]. Shows the green line starting
  /// at the traveller and removes the part already walked behind them.
  List<LatLng> _routeAhead(List<LatLng> geometry, LatLng pos) {
    if (geometry.length < 2) return geometry;
    final match = _matchRoute(pos, geometry);
    final points = <LatLng>[pos];
    if (_distance(pos, match.point) > 4) points.add(match.point);
    for (var i = match.segment + 1; i < geometry.length; i++) {
      points.add(geometry[i]);
    }
    return points.length < 2 ? geometry : points;
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

  /// The crop the buyer is picking up.
  ///
  /// Only present when navigation started from a specific listing (the caller
  /// passed [FarmDirectionsScreen.listingId]). Navigating straight from the map
  /// or a farm profile is not tied to any crop, so nothing is shown as a pickup
  /// rather than guessing at the farm's first available listing.
  CropListing? get _pickup => _listing?.toCropListing();

  bool get _fromListing => _listing != null;

  String get _pickupCrop => _pickup?.cropName ?? _farmName;

  String get _pickupStatusLabel =>
      _statusLabel(_pickup?.status ?? 'NOT_AVAILABLE');

  /// The farm's own listing used as the contact fallback.
  ///
  /// Reaching the farmer is useful even on a map-first trip with no specific
  /// pickup, so the CONTACT FARMERS block falls back to the farm profile's
  /// listings. This never feeds the pickup card — that still requires an
  /// explicit [FarmDirectionsScreen.listingId].
  CropListing? get _fallbackContactListing {
    for (final listing in _profile?.listings ?? const <CropListing>[]) {
      if (listing.status == 'AVAILABLE_NOW') return listing;
    }
    final listings = _profile?.listings ?? const <CropListing>[];
    return listings.isNotEmpty ? listings.first : null;
  }

  static bool _isUsableNumber(String number) =>
      number.trim().isNotEmpty && number != 'N/A';

  String get _farmerName {
    final name = _listing?.farmerName ?? '';
    if (name.trim().isNotEmpty) return name;
    final fallbackFarm = _fallbackContactListing?.farmName ?? '';
    return fallbackFarm.trim().isNotEmpty ? fallbackFarm : _farmName;
  }

  String get _contactNumber {
    final fromListing = _listing?.farmerMobileNumber ?? '';
    if (_isUsableNumber(fromListing)) return fromListing;
    final fallback = _fallbackContactListing?.contactNumber ?? '';
    return _isUsableNumber(fallback) ? fallback : '';
  }

  String? get _contactListingId {
    final id = _listing?.id;
    if (id != null && id.isNotEmpty) return id;
    final fallbackId = _fallbackContactListing?.listingId;
    return (fallbackId != null && fallbackId.isNotEmpty) ? fallbackId : null;
  }

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

  /// Opens the real in-app conversation with the seller, the same thread the
  /// product detail screen's "Message Seller" opens.
  Future<void> _openMessages() async {
    final listingId = _contactListingId;
    if (listingId == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Messaging is only available for a specific crop.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    setState(() => _startingThread = true);
    try {
      final gateway = widget.messagesGateway ?? MessageService.instance;
      final conversation = await gateway.startConversation(listingId);
      if (!mounted) return;
      setState(() => _startingThread = false);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InAppMessagesScreen(
            conversation: conversation,
            gateway: widget.messagesGateway,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _startingThread = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
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
                  const Spacer(),
                  if (kDebugMode)
                    Switch(
                      value: _simulateOn,
                      onChanged: (v) => setState(() => _simulateOn = v),
                      activeThumbColor: AppColors.primaryGreen,
                    ),
                  if (kDebugMode)
                    Text(
                      _simulateOn ? 'SIM ON' : 'SIM OFF',
                      style: const TextStyle(fontSize: 12),
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
                      if (_plan?.hasFerry == true) ...[
                        _ferryWarning(),
                        const SizedBox(height: 16),
                      ],
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

  /// Warns when the selected plan crosses water by boat, and offers the other
  /// mode when it stays on roads/bridges. Walking still navigates as-is; the
  /// buyer just knows to expect a ferry and can switch if they prefer.
  Widget _ferryWarning() {
    final modeLabel = _mode == 'foot' ? 'walking' : 'riding';
    final otherPlan = _mode == 'foot' ? _carPlan : _footPlan;
    final otherModeLabel = _mode == 'foot' ? 'riding' : 'walking';
    final canSwitch = otherPlan != null && otherPlan.hasFerry == false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF9A825)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.directions_boat, color: Color(0xFFF57F17), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Includes a ferry/boat crossing',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF795548),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'This $modeLabel route boards a boat mid-route. Check schedules '
            'and fares before you leave.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF795548)),
          ),
          if (canSwitch) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _mode = _mode == 'foot' ? 'car' : 'foot';
                }),
                icon: const Icon(Icons.signpost, size: 18),
                label: Text(
                  'Use the $otherModeLabel route (roads/bridge) instead',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFF57F17),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMap() {
    final plan = _plan;
    return Stack(
      children: [
        Positioned.fill(
          child: MapLoadingBackground(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _current,
                initialZoom: 14,
                interactionOptions: InteractionOptions(
                  // In manual GPS mode the map must not pan: the drag belongs to
                  // the debug pin, and a competing map pan would win the gesture
                  // arena and move the pin away instead.
                  flags: _manualGps
                      ? (InteractiveFlag.pinchZoom |
                            InteractiveFlag.doubleTapZoom)
                      : InteractiveFlag.all,
                ),
              ),
              children: [
                const MapTileLayer(),
                if (plan != null && plan.geometry.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        // In the journey the line is trimmed behind the
                        // traveller, so its start follows them instead of
                        // staying at the original departure point.
                        points: _step == _Step.journey
                            ? _routeAhead(plan.geometry, _live)
                            : plan.geometry,
                        strokeWidth: 5,
                        color: AppColors.primaryGreen,
                      ),
                    ],
                  ),
                MarkerLayer(
                  // Counter-rotate markers so the arrow always faces "up" — the
                  // travel direction, since the camera is rotated heading-up.
                  rotate: true,
                  markers: [
                    if (_manualGps)
                      _manualUserMarker(_live)
                    else if (_step == _Step.journey)
                      _userMarker(_live)
                    else
                      _userMarker(_current),
                    if (_farmPos != null) _destinationMarker(_farmPos!),
                  ],
                ),
              ],
            ),
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
              main: _isRerouting ? 'Recalculating route…' : _bannerInstruction,
              sub: _isRerouting ? 'You went off the route' : _bannerSub,
            ),
          ),
        if (_manualGps) Positioned(left: 12, top: 84, child: _manualGpsBadge()),
        if (_manualGps) Positioned(right: 12, bottom: 12, child: _debugDpad()),
      ],
    );
  }

  Marker _manualUserMarker(LatLng point) {
    return Marker(
      width: 52,
      height: 52,
      point: point,
      child: GestureDetector(
        key: const ValueKey('manualGpsMarker'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _onManualDragUpdate,
        onPanEnd: _onManualDragEnd,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blue, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.open_with, color: Colors.blue, size: 22),
        ),
      ),
    );
  }

  Widget _manualGpsBadge() {
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _exitManualGps,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app, size: 14, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Manual GPS · drag or arrows',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.close, size: 14, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _debugDpad() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: SizedBox(
        width: 108,
        height: 108,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 36,
              child: _dpadButton(Icons.keyboard_arrow_up, 0),
            ),
            Positioned(
              bottom: 0,
              left: 36,
              child: _dpadButton(Icons.keyboard_arrow_down, 180),
            ),
            Positioned(
              left: 0,
              top: 36,
              child: _dpadButton(Icons.keyboard_arrow_left, 270),
            ),
            Positioned(
              right: 0,
              top: 36,
              child: _dpadButton(Icons.keyboard_arrow_right, 90),
            ),
            const Center(
              child: Icon(Icons.my_location, size: 16, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dpadButton(IconData icon, double bearing) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _startManualMove(bearing),
      onTapUp: (_) => _stopManualMove(),
      onTapCancel: _stopManualMove,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.primaryGreen,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
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
                  if (_simulateOn) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'SIMULATED DEMO — positions are replaying the route '
                      'geometry, not live GPS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
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
                  if (kDebugMode) ...[
                    TextButton.icon(
                      onPressed: _manualGps ? _exitManualGps : _enterManualGps,
                      icon: Icon(
                        _manualGps ? Icons.gps_fixed : Icons.touch_app,
                        size: 18,
                        color: Colors.black45,
                      ),
                      label: Text(
                        _manualGps
                            ? 'Exit manual GPS'
                            : 'Debug: manual GPS (drag or arrows)',
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!_manualGps)
                      TextButton.icon(
                        onPressed: _simulateWrongTurn,
                        icon: const Icon(
                          Icons.alt_route,
                          size: 18,
                          color: Colors.black45,
                        ),
                        label: const Text(
                          'Debug: simulate wrong turn from here',
                          style: TextStyle(color: Colors.black45, fontSize: 12),
                        ),
                      ),
                  ],
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
      backgroundColor: AppColors.searchBackground,
      body: SafeArea(
        child: Column(
          children: [
            _arrivedHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                children: [
                  if (_fromListing) ...[
                    _sectionLabel("YOU'RE HERE TO PICK UP"),
                    const SizedBox(height: 8),
                    _pickupCard(),
                    const SizedBox(height: 24),
                  ] else ...[
                    _noPickupCard(),
                    const SizedBox(height: 24),
                  ],
                  _sectionLabel('CONTACT FARMERS'),
                  const SizedBox(height: 8),
                  if (canContact) _contactCard() else _emptyContactCard(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Back to Browse'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

  Widget _arrivedHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryGreen, AppColors.darkGreen],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 30),
      child: Column(
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            "You've Arrived!",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _farmName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.place_outlined,
                size: 14,
                color: Colors.white.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 4),
              Text(
                _profile?.barangay ?? 'farm location',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 0.6,
        color: AppColors.mutedGreen,
      ),
    );
  }

  Widget _pickupCard() {
    final status = _pickup?.status ?? 'NOT_AVAILABLE';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.successSoft, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.eco,
              color: AppColors.primaryGreen,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pickupCrop,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                _statusChip(status, _pickupStatusLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status, String label) {
    final Color color;
    final Color fill;
    switch (status) {
      case 'AVAILABLE_NOW':
        color = AppColors.primaryGreen;
        fill = AppColors.successSoft;
        break;
      case 'SOON_TO_HARVEST':
        color = AppColors.warningAmber;
        fill = AppColors.warningSoft;
        break;
      default:
        color = AppColors.infoSage;
        fill = AppColors.infoSoft;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _noPickupCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.directions_walk,
              color: AppColors.infoSage,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'You navigated straight to this farm, so no specific crop is '
              'selected for pickup.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactCard() {
    final initial = _farmerName.trim().isEmpty
        ? 'F'
        : _farmerName.trim().characters.first.toUpperCase();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.successSoft, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.successSoft,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _farmerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _contactNumber,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _launchContact('CALL'),
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Call'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                    side: const BorderSide(color: AppColors.primaryGreen),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _startingThread ? null : _openMessages,
                  icon: _startingThread
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(_startingThread ? 'Opening...' : 'Message'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyContactCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_disabled, color: Colors.black38, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No contact number is linked to this farm yet.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        ],
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
