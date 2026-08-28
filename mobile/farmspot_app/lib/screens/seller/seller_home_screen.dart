import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../../../widgets/home_widgets.dart';
import '../../../widgets/seller_widgets.dart';
import '../map_screen.dart';
import '../insights_screen.dart';
import '../profile_screen.dart';
import 'my_farm_screen.dart';

class _SellerListing {
  final String cropName;
  final String farmName;
  final String distance;
  final IconData icon;
  final bool isOwnListing;

  const _SellerListing({
    required this.cropName,
    required this.farmName,
    required this.distance,
    required this.icon,
    this.isOwnListing = false,
  });
}

class SellerHomeScreen extends StatefulWidget {
  const SellerHomeScreen({super.key});

  @override
  State<SellerHomeScreen> createState() => _SellerHomeScreenState();
}

class _SellerHomeScreenState extends State<SellerHomeScreen> {
  int _selectedCategory = 0;
  final _categories = const ['All', 'Leafy Vegetables', 'Fruit Vegetables'];

  final _listings = const [
    _SellerListing(
      cropName: 'Carrot',
      farmName: 'Farm Name',
      distance: '0.4 km away',
      icon: Icons.grass,
      isOwnListing: true,
    ),
    _SellerListing(
      cropName: 'Cabbage',
      farmName: 'Farm Name',
      distance: '0.4 km away',
      icon: Icons.eco,
    ),
    _SellerListing(
      cropName: 'Kangkong',
      farmName: 'Farm Name',
      distance: '0.4 km away',
      icon: Icons.eco_outlined,
    ),
    _SellerListing(
      cropName: 'Chili',
      farmName: 'Farm Name',
      distance: '0.4 km away',
      icon: Icons.local_fire_department,
    ),
    _SellerListing(
      cropName: 'Carrot',
      farmName: 'Farm Name',
      distance: '0.4 km away',
      icon: Icons.grass,
    ),
  ];

  void _handleNavTap(int i) {
    if (i == 0) return; // already on Home
    switch (i) {
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
      case 3:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MyFarmScreen()),
        );
        break;
      case 4:
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCategoryRow(),
                    const SizedBox(height: 20),
                    _buildSectionTitle(),
                    const SizedBox(height: 12),
                    ..._listings.map((l) => _SellerCropCard(listing: l)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SellerBottomNav(
        currentIndex: 0,
        onTap: _handleNavTap,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      color: AppColors.primaryGreen,
      child: const HomeSearchField(),
    );
  }

  Widget _buildCategoryRow() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => CategoryChip(
          label: _categories[i],
          selected: _selectedCategory == i,
          onTap: () => setState(() => _selectedCategory = i),
        ),
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Available now',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        GestureDetector(
          onTap: () {
            debugPrint('See all tapped — no backend wired yet.');
          },
          child: const Row(
            children: [
              Text(
                'see all',
                style: TextStyle(
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward, size: 14, color: AppColors.primaryGreen),
            ],
          ),
        ),
      ],
    );
  }
}

/// Same visual style as the buyer's CropCard, but tags the seller's own
/// listing with a small "your listing" label.
class _SellerCropCard extends StatelessWidget {
  final _SellerListing listing;
  const _SellerCropCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.fieldBorder.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.fieldBorder),
            ),
            child: Icon(listing.icon, color: AppColors.primaryGreen, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crop name:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  listing.farmName,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                if (listing.isOwnListing)
                  Row(
                    children: const [
                      Icon(Icons.storefront, size: 12, color: AppColors.primaryGreen),
                      SizedBox(width: 3),
                      Text(
                        'your listing',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    listing.distance,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'P_status',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
