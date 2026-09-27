import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../models/crop_category.dart';
import '../widgets/home_widgets.dart';
import '../widgets/seller_widgets.dart';
import '../services/listing_service.dart';
import '../services/farm_service.dart';
import '../services/location_service.dart';
import '../services/auth_service.dart';
import '../services/message_service.dart';
import '../widgets/farmspot_loader.dart';
import 'product_detail_screen.dart';
import 'map_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'seller/my_farm_screen.dart';
import 'search_screen.dart';
import 'image_search_screen.dart';
import 'ai_chat_screen.dart';
import 'messages_inbox_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Injectable for tests; the real HTTP-backed service is used when omitted.
  final MessagesGateway? gateway;

  const HomeScreen({super.key, this.gateway});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 0 = "All"; 1..n index into [_categories] (the real API categories).
  int _selectedCategory = 0;
  bool _isSeller = false;

  List<CropCategory> _categories = [];

  List<CropListing> _listings = [];
  bool _isLoading = true;
  String? _errorMessage;
  int? _activeListingCount;

  /// Total unread across every thread, for the Messages entry badge. The home
  /// feed never blocks on it — a failure just leaves the badge hidden.
  int _unreadMessages = 0;

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadSellerStatus();
    _loadCategories();
    _loadUnreadMessages();
  }

  /// Counts unread messages for the Messages entry. Deliberately failure
  /// tolerant: messaging being unreachable must never break the feed.
  Future<void> _loadUnreadMessages() async {
    try {
      final gateway = widget.gateway ?? MessageService.instance;
      final threads = await gateway.fetchConversations();
      if (!mounted) return;
      setState(() =>
          _unreadMessages = threads.fold(0, (sum, t) => sum + t.unreadCount));
    } catch (_) {
      // Leave the badge hidden.
    }
  }

  /// Real crop categories for the filter chips. Failure-tolerant: on error the
  /// row simply shows "All" so the feed still works.
  Future<void> _loadCategories() async {
    try {
      final categories = await ListingService.fetchCropCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // Chips fall back to just "All".
    }
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

  List<CropListing> get _filteredListings {
    if (_selectedCategory == 0) return _listings;
    final categoryId = _categories[_selectedCategory - 1].id;
    return _listings.where((l) => l.categoryId == categoryId).toList();
  }

  void _openDetail(CropListing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(listing: listing),
      ),
    );
  }

  Future<void> _loadListings({String? search, bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final listings = await ListingService.fetchListings(search: search);
      if (!mounted) return;
      // Resolve the real distance BEFORE the grid renders (the existing load
      // spinner covers the wait): one fetch of the public farm pins + one buyer
      // GPS lookup services the whole feed, so the seeded "0.4 km away" never
      // flashes on screen. Cards whose farm can't be matched keep the seed
      // label rather than hiding the line (same fallback as the detail screen).
      final crops = await _resolveDistances(
          listings.map((l) => l.toCropListing()).toList());
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _listings = crops;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Pull-to-refresh: reload the feed while keeping current content on screen.
  Future<void> _refresh() async {
    await _loadListings(showLoading: false);
    await _loadSellerStatus();
    await _loadCategories();
    await _loadUnreadMessages();
  }

  /// Swaps every listing's seeded "0.4 km away" for the real haversine
  /// distance to its farm, computing buyer GPS + the public pin list once for
  /// the whole feed. Silent on failure: unresolvable cards keep their current
  /// label (matching what the profile/detail screens show while unresolvable).
  Future<List<CropListing>> _resolveDistances(List<CropListing> listings) async {
    try {
      final farms = await FarmService.fetchPublicFarms();
      if (farms.isEmpty) return listings;
      final you = await LocationService.defaultBuyerPosition();
      final byId = {for (final f in farms) f.id: f};
      return listings.map((l) {
        final farm = l.farmId == null ? null : byId[l.farmId];
        if (farm == null) return l;
        final km =
            LocationService.distanceKm(you, LatLng(farm.latitude, farm.longitude));
        return l.withDistance(LocationService.distanceLabel(km));
      }).toList();
    } catch (_) {
      // Offline / no pins: keep the seeded labels rather than crash the feed.
      return listings;
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
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
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
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiChatScreen()),
                  );
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
      child: Row(
        children: [
          Expanded(
            child: HomeSearchField(
              tapToOpen: true,
              onSearchTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
              onCameraTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImageSearchScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          _buildMessagesBell(),
        ],
      ),
    );
  }

  /// Messages live in the header rather than in the feed because a conversation
  /// is not browseable content: it has to be reachable from anywhere on this
  /// screen, and its unread count is only useful while it is in view. A bell
  /// also keeps it visually distinct from the AI chat FAB below, which would
  /// otherwise be a second chat-bubble icon meaning something else.
  ///
  /// The entry is deliberately role-agnostic. Selling and buying are not
  /// exclusive — a farmer can be the buyer in one thread and the seller in
  /// another, and can message another farmer entirely — so the inbox tags each
  /// thread with the role that user is playing in it rather than this screen
  /// guessing from a single account-wide flag.
  Widget _buildMessagesBell() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _openInbox,
            child: const SizedBox(
              width: 46,
              height: 46,
              child: Icon(Icons.notifications_none_rounded,
                  color: Colors.black54, size: 24),
            ),
          ),
        ),
        if (_unreadMessages > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primaryGreen, width: 2),
              ),
              child: Center(
                child: Text(
                  _unreadMessages > 99 ? '99+' : '$_unreadMessages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openInbox() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagesInboxScreen(gateway: widget.gateway),
      ),
    );
    // Threads may have been read since the badge was counted.
    if (mounted) _loadUnreadMessages();
  }

  Widget _buildCategoryRow() {
    // Index 0 is always "All"; each real category from the API follows it.
    final chipCount = _categories.length + 1;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chipCount,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return CategoryChip(
              label: 'All',
              selected: _selectedCategory == 0,
              onTap: () => setState(() => _selectedCategory = 0),
            );
          }
          final category = _categories[i - 1];
          return CategoryChip(
            label: category.name,
            selected: _selectedCategory == i,
            onTap: () => setState(() => _selectedCategory = i),
          );
        },
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
        child: FarmSpotLoader(),
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

    return CropLadderGrid(
      listings: _filteredListings,
      onTap: _openDetail,
    );
  }
}