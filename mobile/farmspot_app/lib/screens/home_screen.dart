import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import 'product_detail_screen.dart';
import 'map_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedCategory = 0;

  final _categories = const ['All', 'Leafy Vegetables', 'Fruit Vegetables'];

  // Placeholder data — replace with real API results later.
  final _listings = const [
    CropListing(
      cropName: 'Carrot',
      farmName: 'Farm Name',
      placeholderIcon: Icons.grass,
    ),
    CropListing(
      cropName: 'Cabbage',
      farmName: 'Farm Name',
      placeholderIcon: Icons.eco,
    ),
    CropListing(
      cropName: 'Kangkong',
      farmName: 'Farm Name',
      placeholderIcon: Icons.eco,
    ),
    CropListing(
      cropName: 'Chili',
      farmName: 'Farm Name',
      placeholderIcon: Icons.local_fire_department,
    ),
    CropListing(
      cropName: 'Carrot',
      farmName: 'Farm Name',
      placeholderIcon: Icons.grass,
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
        child: Stack(
          children: [
            Column(
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
                        ..._listings.map(
                          (listing) => CropCard(
                            listing: listing,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProductDetailScreen(listing: listing),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Temporary floating chat/support button.
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton(
                backgroundColor: AppColors.primaryGreen,
                onPressed: () {
                  debugPrint('Chat support tapped — no backend wired yet.');
                },
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FarmSpotBottomNav(
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
