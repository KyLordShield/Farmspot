import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import '../map_screen.dart';
import '../insights_screen.dart';
import '../profile_screen.dart';
import 'seller_home_screen.dart';
import 'add_crop_screen.dart';

class _MyCrop {
  final String name;
  final IconData icon;
  final AvailabilityStatus status;

  const _MyCrop({required this.name, required this.icon, required this.status});
}

class MyFarmScreen extends StatefulWidget {
  const MyFarmScreen({super.key});

  @override
  State<MyFarmScreen> createState() => _MyFarmScreenState();
}

class _MyFarmScreenState extends State<MyFarmScreen> {
  final List<_MyCrop> _crops = const [
    _MyCrop(name: 'Cabbage', icon: Icons.eco, status: AvailabilityStatus.availableNow),
  ];

  void _handleNavTap(int i) {
    if (i == 3) return; // already on My Farm
    switch (i) {
      case 0:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SellerHomeScreen()),
        );
        break;
      case 1:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MapScreen()),
        );
        break;
      case 2:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const InsightsScreen()),
        );
        break;
      case 4:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
        break;
    }
  }

  Future<void> _addCrop() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddCropScreen(isFirstCrop: false)),
    );
    // UI-only for now — newly added crop isn't persisted to this list yet.
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
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF6EC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primaryGreen,
                          child: Icon(Icons.agriculture, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Belle Farm',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                'Sudlon dos. Maraag',
                                style: TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Live',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Listings',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: _addCrop,
                        icon: const Icon(Icons.add, size: 16, color: AppColors.primaryGreen),
                        label: const Text(
                          'Add Crop',
                          style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._crops.map((c) => _CropListTile(crop: c)),
                  if (_crops.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          'No crops listed yet. Tap "Add Crop" to get started.',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SellerBottomNav(
        currentIndex: 3,
        onTap: _handleNavTap,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      color: AppColors.primaryGreen,
      child: const Text(
        'My Farm',
        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CropListTile extends StatelessWidget {
  final _MyCrop crop;
  const _CropListTile({required this.crop});

  @override
  Widget build(BuildContext context) {
    final statusInfo = switch (crop.status) {
      AvailabilityStatus.availableNow => ('Available Now', AppColors.primaryGreen),
      AvailabilityStatus.soonToHarvest => ('Soon to Harvest', Colors.orange),
      AvailabilityStatus.notAvailable => ('Not Available', Colors.grey),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.green.shade50,
            child: Icon(crop.icon, color: AppColors.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(crop.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusInfo.$2.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              statusInfo.$1,
              style: TextStyle(fontSize: 11, color: statusInfo.$2, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
