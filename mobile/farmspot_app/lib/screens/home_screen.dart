import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../models/crop_category.dart';
import '../models/home_filters.dart';
import '../widgets/home_filter_sheet.dart';
import '../widgets/home_widgets.dart';
import '../widgets/seller_widgets.dart';
import '../services/listing_service.dart';
import '../services/farm_service.dart';
import '../services/location_service.dart';
import '../services/session_state.dart';
import '../services/message_service.dart';
import '../services/notification_service.dart';
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
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Injectable for tests; the real HTTP-backed service is used when omitted.
  final MessagesGateway? gateway;

  /// Same seam for the notification bell's badge, so a header test can pin the
  /// count without a server. Deliberately a separate field rather than a second
  /// gateway on one param: the two inboxes are independent, and sharing a
  /// field is what would tempt the badge to reuse the wrong count.
  final NotificationsGateway? notificationGateway;

  const HomeScreen({super.key, this.gateway, this.notificationGateway});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The Filter button's state: category, availability and sort in one value.
  ///
  /// One value rather than three fields so the sheet and the feed cannot
  /// disagree about what is showing.
  HomeFilters _filters = HomeFilters.none;

  List<CropCategory> _categories = [];

  List<CropListing> _listings = [];
  bool _isLoading = true;
  String? _errorMessage;

  /// Total unread across every thread, for the Messages entry badge. The home
  /// feed never blocks on it — a failure just leaves the badge hidden.
  int _unreadMessages = 0;

  /// Unread notifications, for the bell. Kept apart from [_unreadMessages] on
  /// purpose: chat and the notification inbox are different lists with
  /// different endpoints, so one number cannot stand in for the other.
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadListings();
    _loadCategories();
    _loadUnreadMessages();
    _loadUnreadNotifications();
  }

  /// Counts unread messages for the Messages entry. Deliberately failure
  /// tolerant: messaging being unreachable must never break the feed.
  Future<void> _loadUnreadMessages() async {
    try {
      final gateway = widget.gateway ?? MessageService.instance;
      final threads = await gateway.fetchConversations();
      if (!mounted) return;
      setState(
        () =>
            _unreadMessages = threads.fold(0, (sum, t) => sum + t.unreadCount),
      );
    } catch (_) {
      // Leave the badge hidden.
    }
  }

  /// Counts unread notifications for the bell badge. Uses the dedicated
  /// unread-count endpoint rather than paging the inbox, so opening Home costs
  /// one small request instead of downloading 20 rows of text. Failure tolerant
  /// for the same reason as the messages badge: the header must survive.
  Future<void> _loadUnreadNotifications() async {
    try {
      final api = widget.notificationGateway ?? NotificationService.instance;
      final count = await api.fetchUnreadCount();
      if (!mounted) return;
      setState(() => _unreadNotifications = count);
    } catch (_) {
      // Leave the badge hidden.
    }
  }

  /// Real crop categories, for the Filter sheet's category list.
  /// Failure-tolerant: on error the sheet simply offers no categories and the
  /// rest of the feed still works.
  Future<void> _loadCategories() async {
    try {
      final categories = await ListingService.fetchCropCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // The category group in the sheet stays empty.
    }
  }

  List<CropListing> get _filteredListings {
    // Availability and sort are already applied by the server, so this only
    // has to narrow by category. Comparing the id directly (rather than an
    // index into _categories) also means a category whose row has not loaded
    // yet cannot throw here.
    final categoryId = _filters.categoryId;
    if (categoryId == null) return _listings;
    return _listings.where((l) => l.categoryId == categoryId).toList();
  }

  void _openDetail(CropListing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(listing: listing)),
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
      // Only the two groups the server owns are sent. Category is deliberately
      // not: it is applied locally by _filteredListings, so sending it too
      // would narrow the feed twice over.
      final listings = await ListingService.fetchListings(
        search: search,
        availability: _filters.availability?.wireValue,
        sort: _filters.sort,
      );
      if (!mounted) return;
      // Resolve the real distance BEFORE the grid renders (the existing load
      // spinner covers the wait): one fetch of the public farm pins + one buyer
      // GPS lookup services the whole feed, so the seeded "0.4 km away" never
      // flashes on screen. Cards whose farm can't be matched keep the seed
      // label rather than hiding the line (same fallback as the detail screen).
      final crops = await _resolveDistances(
        listings.map((l) => l.toCropListing()).toList(),
      );
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
    // The role is not refetched here. It is shared session state that survives
    // navigation, so re-deriving it on refresh is what used to make the nav
    // flicker.
    await _loadCategories();
    await _loadUnreadMessages();
    await _loadUnreadNotifications();
  }

  /// Swaps every listing's seeded "0.4 km away" for the real haversine
  /// distance to its farm, computing buyer GPS + the public pin list once for
  /// the whole feed. Silent on failure: unresolvable cards keep their current
  /// label (matching what the profile/detail screens show while unresolvable).
  Future<List<CropListing>> _resolveDistances(
    List<CropListing> listings,
  ) async {
    try {
      final farms = await FarmService.fetchPublicFarms();
      if (farms.isEmpty) return listings;
      final you = await LocationService.defaultBuyerPosition();
      final byId = {for (final f in farms) f.id: f};
      return listings.map((l) {
        final farm = l.farmId == null ? null : byId[l.farmId];
        if (farm == null) return l;
        final km = LocationService.distanceKm(
          you,
          LatLng(farm.latitude, farm.longitude),
        );
        return l.withDistance(LocationService.distanceLabel(km));
      }).toList();
    } catch (_) {
      // Offline / no pins: keep the seeded labels rather than crash the feed.
      return listings;
    }
  }

  void _handleNavTap(int i) {
    if (i == 0) return; // already on Home
    // Read the role at tap time rather than from a field captured at build
    // time. The two nav layouts index differently (4 buyer tabs vs 5 seller
    // tabs), so a stale read here sends the user to the wrong screen.
    if (SessionState.instance.isSeller) {
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
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const MapScreen()));
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
            // Customer support / AI assistant. The headset mark is deliberate:
            // it no longer reads as a second, competing "chat bubble" now that
            // real conversations live behind the messages button in the header.
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton(
                backgroundColor: AppColors.primaryGreen,
                // Pinned explicitly: the theme's default foreground was the
                // muddy grey that disappeared into the green.
                foregroundColor: Colors.white,
                tooltip: 'Customer support',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiChatScreen()),
                  );
                },
                child: const Icon(
                  Icons.support_agent,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: SessionState.instance,
        builder: (context, _) => SessionState.instance.isSeller
            ? SellerBottomNav(currentIndex: 0, onTap: _handleNavTap)
            : FarmSpotBottomNav(currentIndex: 0, onTap: _handleNavTap),
      ),
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
              // Trimmed from 46 so both header buttons fit beside it while the
              // bar still reads as a long, easily-tapped search field.
              height: 40,
              onSearchTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SearchScreen()));
              },
              onCameraTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImageSearchScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          _buildMessagesButton(),
          const SizedBox(width: 4),
          _buildNotificationsButton(),
        ],
      ),
    );
  }

  /// Icon-only header action. No filled circle behind it: the glyph sits
  /// straight on the green header, which is both lighter on the eye and gives
  /// the search bar back the width the circles were eating. The 40x40 box is
  /// kept as the tap target even though the icon is only 22px, so it stays
  /// comfortable to hit.
  ///
  /// The Material is transparent rather than white: an InkWell needs a Material
  /// ancestor to paint its ripple, and the nearest one here is the Scaffold's,
  /// which sits *behind* the green header and would make the splash invisible.
  Widget _buildHeaderButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Widget? badge,
  }) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 40,
                height: 40,
                // White now that there is no white plate behind it: the glyph
                // sits directly on the green header, where the old black54
                // would have been nearly unreadable.
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            ),
          ),
          // IgnorePointer is load-bearing: the badge is decoration, not a
          // control, and without it the badge can sit over the icon and swallow
          // the tap on the button underneath.
          if (badge != null)
            Positioned(right: 0, top: 0, child: IgnorePointer(child: badge)),
        ],
      ),
    );
  }

  Widget _buildMessagesButton() {
    return _buildHeaderButton(
      icon: Icons.chat_bubble_outline_rounded,
      tooltip: 'Messages',
      onTap: _openInbox,
      badge: _unreadMessages > 0 ? _buildUnreadBadge(_unreadMessages) : null,
    );
  }

  Widget _buildNotificationsButton() {
    return _buildHeaderButton(
      icon: Icons.notifications_none_rounded,
      tooltip: 'Notifications',
      onTap: _openNotifications,
      badge: _unreadNotifications > 0
          ? _buildUnreadBadge(_unreadNotifications)
          : null,
    );
  }

  /// Opens the inbox and recounts the badge on the way back: opening rows
  /// marks them read, so the number the header is holding is already stale by
  /// the time the screen pops.
  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            NotificationsScreen(gateway: widget.notificationGateway),
      ),
    );
    if (mounted) _loadUnreadNotifications();
  }

  /// Shared by both header badges, so the two buttons cannot drift apart in
  /// size or in the 99+ cap.
  Widget _buildUnreadBadge(int count) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }

  /// Messages live in the header rather than in the feed because a conversation
  /// is not browseable content: it has to be reachable from anywhere on this
  /// screen, and its unread count is only useful while it is in view.
  ///
  /// The entry is deliberately role-agnostic. Selling and buying are not
  /// exclusive — a farmer can be the buyer in one thread and the seller in
  /// another, and can message another farmer entirely — so the inbox tags each
  /// thread with the role that user is playing in it rather than this screen
  /// guessing from a single account-wide flag.
  Future<void> _openInbox() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagesInboxScreen(gateway: widget.gateway),
      ),
    );
    // Threads may have been read since the badge was counted.
    if (mounted) _loadUnreadMessages();
  }

  /// Opens the filter popup and adopts whatever it returns.
  Future<void> _openFilters() async {
    final picked = await showHomeFilterSheet(
      context,
      current: _filters,
      categories: _categories,
    );

    // Dismissed, or applied without changing anything.
    if (picked == null || !mounted || picked == _filters) return;

    // Availability is the server's half, so it needs a refetch. Category alone
    // does not, and neither does a re-sort on its own — but a re-sort the
    // server did not perform has to be asked for, or the order on screen would
    // silently stay whatever the last request returned.
    final mustRefetch = picked.needsRefetch || picked.sort != _filters.sort;

    setState(() => _filters = picked);
    if (mustRefetch) {
      await _loadListings(showLoading: false);
    }
  }

  /// The display name of the applied category, for the heading and the button.
  ///
  /// Null when the category list has not loaded, or when the applied id is no
  /// longer among the categories — in which case the UI falls back to wording
  /// that does not name it.
  String? get _appliedCategoryName {
    final id = _filters.categoryId;
    if (id == null) return null;
    for (final category in _categories) {
      if (category.id == id) return category.name;
    }
    return null;
  }

  /// Names what the feed is actually showing.
  ///
  /// The heading used to be a fixed "Available now", which was only ever true
  /// when nothing was filtered. With the Filter button that is no longer safe:
  /// a buyer who picks "Soon to harvest" would read a heading claiming the feed
  /// is available now. So it reports the category and availability that are
  /// really applied, and falls back to the old default when neither is.
  String get _feedHeading {
    final parts = <String>[
      ?_appliedCategoryName,
      ?_filters.availability?.label,
    ];
    if (parts.isEmpty) return 'Available now';
    return parts.join(' • ');
  }

  Widget _buildSectionTitle() {
    return Row(
      children: [
        // Expanded so the heading yields space to the Filter button on a narrow
        // phone or at a large system text scale, instead of overflowing.
        Expanded(
          child: Text(
            _feedHeading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        HomeFilterButton(
          filters: _filters,
          categoryName: _appliedCategoryName,
          onTap: _openFilters,
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
              TextButton(onPressed: _loadListings, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return CropLadderGrid(listings: _filteredListings, onTap: _openDetail);
  }
}
