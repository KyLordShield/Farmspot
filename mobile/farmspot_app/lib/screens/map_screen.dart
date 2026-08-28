import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'home_screen.dart';
import 'farm_directions_screen.dart';

/// Simple placeholder model for a farm pin shown on the map / listing.
class FarmPin {
  final String name;
  final String distanceKm;
  final List<String> cropNames;

  const FarmPin({
    required this.name,
    required this.distanceKm,
    required this.cropNames,
  });
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // 0 = Listing view toggle, 1 = Map view toggle (both render the same
  // placeholder map for now — swap in a real Listing view later).
  int _viewToggle = 1;

  final _farm = const FarmPin(
    name: 'Mr. A Farm',
    distanceKm: '0.4 km',
    cropNames: ['Crop name: P_status', 'Crop name: P_status'],
  );

  void _handleNavTap(int i) {
    if (i == 1) return; // already on Map
    switch (i) {
      case 0:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        break;
      case 2:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const InsightsScreen()),
        );
        break;
      case 3:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  _MapPlaceholder(pinLabel: _farm.name),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _FarmCard(
                      farm: _farm,
                      onDirections: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                FarmDirectionsScreen(farmName: _farm.name),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FarmSpotBottomNav(
        currentIndex: 1,
        onTap: _handleNavTap,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: AppColors.primaryGreen,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Farm Map',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          _ToggleGroup(
            selected: _viewToggle,
            onChanged: (i) => setState(() => _viewToggle = i),
          ),
        ],
      ),
    );
  }
}

/// "Listing | Map" segmented toggle used in the header.
class _ToggleGroup extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ToggleGroup({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('Listing', 0),
          _segment('Map', 1),
        ],
      ),
    );
  }

  Widget _segment(String label, int index) {
    final bool isSelected = selected == index;
    return GestureDetector(
      onTap: () => onChanged(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

/// Placeholder "map" surface — a stylised grey map with a couple of pin
/// markers so the screen reads correctly without a real Maps SDK wired up.
class _MapPlaceholder extends StatelessWidget {
  final String pinLabel;
  const _MapPlaceholder({required this.pinLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFE8ECE6),
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _FakeRoadsPainter(),
          ),
          Positioned(
            top: 60,
            left: 40,
            child: _pin(Colors.orange, Icons.location_on),
          ),
          Positioned(
            top: 140,
            right: 60,
            child: _pin(Colors.redAccent, Icons.location_on),
          ),
          Align(
            alignment: const Alignment(0, -0.1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pin(AppColors.primaryGreen, Icons.location_on, size: 40),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    pinLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pin(Color color, IconData icon, {double size = 30}) {
    return Icon(icon, color: color, size: size);
  }
}

class _FakeRoadsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(0, size.height * 0.3),
      Offset(size.width, size.height * 0.25),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.2, 0),
      Offset(size.width * 0.35, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.7, 0),
      Offset(size.width * 0.6, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bottom info card shown over the map for the nearest farm.
class _FarmCard extends StatelessWidget {
  final FarmPin farm;
  final VoidCallback onDirections;

  const _FarmCard({required this.farm, required this.onDirections});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  farm.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                farm.distanceKm,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...farm.cropNames.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  c,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onDirections,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Directions',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
