import 'package:flutter/material.dart';
import '../theme.dart';

/// Handles the three-step navigation flow shown when a buyer taps
/// "Directions" on a farm: pre-navigation summary -> live journey ->
/// arrived / pickup confirmation. UI-only — no real routing/backend yet.
class FarmDirectionsScreen extends StatefulWidget {
  final String farmName;
  const FarmDirectionsScreen({super.key, required this.farmName});

  @override
  State<FarmDirectionsScreen> createState() => _FarmDirectionsScreenState();
}

enum _Step { direction, journey, arrived }

class _FarmDirectionsScreenState extends State<FarmDirectionsScreen> {
  _Step _step = _Step.direction;

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _Step.direction:
        return _DirectionView(
          farmName: widget.farmName,
          onStartNavigation: () => setState(() => _step = _Step.journey),
        );
      case _Step.journey:
        return _JourneyView(
          onArrived: () => setState(() => _step = _Step.arrived),
          onCancel: () => Navigator.of(context).pop(),
        );
      case _Step.arrived:
        return _ArrivedView(
          farmName: widget.farmName,
          onBackToBrowse: () =>
              Navigator.of(context).popUntil((r) => r.isFirst),
        );
    }
  }
}

/// Shared fake-map background used across all three steps.
class _RouteMap extends StatelessWidget {
  final Widget? topBanner;
  final String etaLabel;

  const _RouteMap({this.topBanner, required this.etaLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8ECE6),
      child: Stack(
        children: [
          CustomPaint(size: Size.infinite, painter: _RoutePainter()),
          if (topBanner != null)
            Positioned(top: 16, left: 16, right: 16, child: topBanner!),
          Align(
            alignment: const Alignment(0, 0.3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                etaLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment(0, 0.85),
            child: Icon(Icons.location_on, color: Colors.redAccent, size: 40),
          ),
          const Align(
            alignment: Alignment(-0.3, -0.6),
            child: Icon(Icons.circle, color: Colors.blue, size: 16),
          ),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.3, size.height * 0.15)
      ..quadraticBezierTo(
        size.width * 0.1,
        size.height * 0.4,
        size.width * 0.5,
        size.height * 0.55,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.65,
        size.width * 0.55,
        size.height * 0.9,
      );

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.orangeAccent
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.srcOver,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// STEP 1 — pre-navigation summary.
class _DirectionView extends StatelessWidget {
  final String farmName;
  final VoidCallback onStartNavigation;

  const _DirectionView({required this.farmName, required this.onStartNavigation});

  @override
  Widget build(BuildContext context) {
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
            SizedBox(
              height: 260,
              child: _RouteMap(etaLabel: '40 min'),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    farmName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'farm location',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoPill(label: '40 min', sub: 'walking'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoPill(label: '25 min', sub: 'riding'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onStartNavigation,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String sub;
  const _InfoPill({required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          Text(sub, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

/// STEP 2 — live journey / turn-by-turn.
class _JourneyView extends StatelessWidget {
  final VoidCallback onArrived;
  final VoidCallback onCancel;

  const _JourneyView({required this.onArrived, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _RouteMap(
                etaLabel: '40 min',
                topBanner: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.arrow_upward, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Head Straight on somewhere Rd',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Then turn right in 60m',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: const [
                      _JourneyStat(value: '30 min', label: 'ETA'),
                      _JourneyStat(value: '0.3 km', label: 'Remaining'),
                      _JourneyStat(value: 'Walking', label: ''),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onArrived,
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
                    onPressed: onCancel,
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
}

class _JourneyStat extends StatelessWidget {
  final String value;
  final String label;
  const _JourneyStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        if (label.isNotEmpty)
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

/// STEP 3 — arrived / pickup confirmation.
class _ArrivedView extends StatelessWidget {
  final String farmName;
  final VoidCallback onBackToBrowse;

  const _ArrivedView({required this.farmName, required this.onBackToBrowse});

  @override
  Widget build(BuildContext context) {
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
                '$farmName · farm location',
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
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cabbage',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Available Now',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
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
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primaryGreen),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Little A',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                              Text(
                                '0900-000-0000',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        _circleAction(Icons.phone),
                        const SizedBox(width: 8),
                        _circleAction(Icons.chat_bubble_outline),
                      ],
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
                  onPressed: onBackToBrowse,
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

  Widget _circleAction(IconData icon) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primaryGreen,
      child: Icon(icon, color: Colors.white, size: 16),
    );
  }
}
