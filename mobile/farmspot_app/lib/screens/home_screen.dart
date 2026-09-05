import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import '../widgets/seller_widgets.dart';
import '../services/listing_service.dart';
import '../services/auth_service.dart';
import 'product_detail_screen.dart';
import 'map_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'seller/my_farm_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedCategory = 0;
  bool _isSeller = false;

  final _categories = const ['All', 'Leafy Vegetables', 'Fruit Vegetables'];

  List<CropListing> _listings = [];
  bool _isLoading = true;
  String? _errorMessage;
  final _searchController = TextEditingController();
  int? _activeListingCount;

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadSellerStatus();
  }

  /// Fetch fresh seller status so the bottom nav (seller vs buyer) is correct
  /// on the very first screen after login, without waiting for ProfileScreen.
  Future<void> _loadSellerStatus() async {
    final isSeller = await AuthService.isSeller();
    if (!mounted) return;
    setState(() => _isSeller = isSeller);
    if (isSeller) {
      await _loadActiveListingCount();
    }
  }

  /// Seller-only acknowledgment: a real count of the user's own live listings
  /// (everything not NOT_AVAILABLE). Full management lives on MyFarmScreen, so
  /// this stays a small banner — it never duplicates the marketplace feed.
  Future<void> _loadActiveListingCount() async {
    try {
      final listings = await ListingService.fetchMyListings();
      if (!mounted) return;
      setState(() {
        _activeListingCount =
            listings.where((l) => l.status != 'NOT_AVAILABLE').length;
      });
    } catch (_) {
      // Fall back to the generic seller text if the count can't be fetched.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CropListing> get _filteredListings {
    if (_selectedCategory == 0) return _listings;
    final categoryLabel = _categories[_selectedCategory].toLowerCase();
    return _listings
        .where(
          (l) =>
              categoryLabel.contains(l.cropType.toLowerCase()) ||
              l.cropType.toLowerCase().contains(categoryLabel),
        )
        .toList();
  }

  void _openDetail(CropListing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(listing: listing),
      ),
    );
  }

  Future<void> _loadListings({String? search}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final listings = await ListingService.fetchListings(search: search);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _listings = listings.map((l) => l.toCropListing()).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _handleNavTap(int i) {
    if (i == 0) return; // already on Home
    if (_isSeller) {
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
      return;
    }

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
                        if (_isSeller) ...[
                          const SizedBox(height: 14),
                          _buildSellerBanner(),
                        ],
                        const SizedBox(height: 20),
                        _buildSectionTitle(),
                        const SizedBox(height: 12),
                        _buildListingsSection(),
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
      bottomNavigationBar: _isSeller
          ? SellerBottomNav(currentIndex: 0, onTap: _handleNavTap)
          : FarmSpotBottomNav(currentIndex: 0, onTap: _handleNavTap),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      color: AppColors.primaryGreen,
      child: HomeSearchField(
        controller: _searchController,
        onSubmitted: (value) => _loadListings(search: value),
        onSearchTap: () => _loadListings(search: _searchController.text),
      ),
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

  Widget _buildSellerBanner() {
    final count = _activeListingCount;
    final label = count == null
        ? 'You are a seller on FarmSpot'
        : 'You have $count active listing${count == 1 ? '' : 's'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront, size: 20, color: AppColors.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
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

  Widget _buildListingsSection() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 120),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 120),
        child: Center(
          child: Column(
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              TextButton(
                onPressed: _loadListings,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return CropCardGrid(
      listings: _filteredListings,
      onTap: _openDetail,
    );
  }
}
