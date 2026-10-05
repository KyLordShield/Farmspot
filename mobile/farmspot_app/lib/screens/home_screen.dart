import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../models/crop_category.dart';
import '../models/farm_pin.dart';
import '../models/home_filters.dart';
import '../models/listing_review.dart';
import '../widgets/home_filter_sheet.dart';
import '../widgets/home_widgets.dart';
import '../widgets/seller_widgets.dart';
import '../services/home_feed_gateway.dart';
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

  /// The paged feed's data source.
  ///
  /// Separate from [gateway] on purpose. This screen talks to three unrelated
  /// backends — listings, conversations, notifications — and folding them into
  /// one injectable object would make every test that cares about the header
  /// badge also stand up a fake feed, and every feed test care about message
  /// counts.
  final HomeFeedGateway? feedGateway;

  const HomeScreen({
    super.key,
    this.gateway,
    this.notificationGateway,
    this.feedGateway,
  });

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

  /// Everything the buyer has seen so far, oldest page first.
  ///
  /// One list, not a list of pages: the ladder renders a flat sequence of
  /// rungs, so a page boundary is a network concern and has no business being
  /// visible in the widget tree.
  List<CropListing> _listings = [];

  /// True only for the first page. Pages after it append under a footer so the
  /// cards already on screen never flash away to a spinner.
  bool _isLoading = true;

  /// A page request that failed. Split in two because the two are shown in
  /// different places and mean different things: [_errorMessage] replaces the
  /// whole feed, [_loadMoreError] sits under it.
  String? _errorMessage;
  String? _loadMoreError;

  /// Whether a page request is in flight for page [_page] + 1.
  bool _isLoadingMore = false;

  /// The last page fetched, and the last page the server says exists.
  ///
  /// Both are needed. Trusting only the server's number means a dropped final
  /// page leaves the feed permanently "one scroll away" from a request that
  /// always returns nothing.
  int _page = 0;
  int _lastPage = 1;

  static const int _pageSize = 10;

  /// How close to the bottom the feed gets before the next page is asked for.
  ///
  /// Half a screen's worth of cards early. Starting the request only when the
  /// last card is already visible guarantees the buyer sees the spinner at the
  /// bottom before they see content, which is the thing paging is supposed to
  /// stop.
  static const double _loadMoreThreshold = 600;

  final ScrollController _scrollController = ScrollController();

  /// Public farm pins and the buyer's position, resolved once per feed load.
  ///
  /// Both are per-session constants, not per-listing: the same farm list and
  /// the same GPS fix serve every card in every page. Resolving them inside the
  /// per-page loop is what would turn one request into one request per page.
  List<FarmPin> _farms = [];
  LatLng? _buyerPosition;
  bool _distanceLookupDone = false;

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
    _scrollController.addListener(_onScroll);
    _loadListings();
    _loadCategories();
    _loadUnreadMessages();
    _loadUnreadNotifications();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  HomeFeedGateway get _feed => widget.feedGateway ?? const ListingFeedGateway();

  /// Asks for the next page once the buyer is close enough to the bottom.
  ///
  /// The guards live here and not only at the call site because a scroll
  /// listener fires on every frame of a fling: without them one flick would
  /// start a dozen requests and append the same page a dozen times.
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // A failed page stays failed until it is asked for again. Without this the
    // error footer itself is the trigger: it appears, it makes the feed taller,
    // the scroll listener fires, and the same failing page is requested again
    // and again for as long as the buyer sits there.
    if (_loadMoreError != null) return;

    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels > _loadMoreThreshold) return;
    _loadMore();
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
    // The server now owns the category filter, because a page cannot be filtered
    // by the client: a page of ten ranked listings legitimately holds none of
    // the chosen category, and narrowing those ten locally shows an empty feed
    // that looks broken rather than filtered. This remains as a cheap guard for
    // a listing whose category arrives after the filter was applied.
    final categoryId = _filters.categoryId;
    if (categoryId == null) return _listings;
    return _listings.where((l) => l.categoryId == categoryId).toList();
  }

  void _openDetail(CropListing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          listing: listing,
          // The feed keeps its own copy of every listing, so a review written on
          // the detail screen left this card showing the old average until a
          // pull-to-refresh. Patched here instead of refetching the whole feed:
          // one listing changed, and a refetch would also throw away the scroll
          // position and the resolved distances.
          onRatingsChanged: (summary) => _applyRating(listing, summary),
        ),
      ),
    );
  }

  /// Swaps the fresh average onto the card the buyer came from.
  void _applyRating(CropListing listing, RatingSummary summary) {
    final listingId = listing.listingId;
    if (!mounted || listingId == null || listingId.isEmpty) return;

    setState(() {
      _listings = [
        for (final row in _listings)
          if (row.listingId == listingId) row.withRatings(summary) else row,
      ];
    });
  }

  /// Whether another page is worth asking for.
  bool get _hasMore => _page > 0 && _page < _lastPage;

  Future<void> _loadListings({String? search, bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _loadMoreError = null;
      });
    }

    try {
      final page = await _feed.fetchFeedPage(
        page: 1,
        perPage: _pageSize,
        search: search,
        category: _filters.categoryId,
        availability: _filters.availability?.wireValue,
        sort: _filters.sort,
        // Ranking replaces the explicit ordering, so asking for both would
        // leave the sheet showing an order the feed is not in.
        personalized: _filters.sort == HomeSortMode.latest,
      );

      // Resolve the real distance BEFORE the feed renders: one fetch of the
      // public farm pins + one buyer GPS lookup services every page, so the
      // seeded "0.4 km away" never flashes on screen. Cards whose farm can't be
      // matched keep the seed label rather than hiding the line (same fallback
      // as the detail screen).
      final crops = await _resolveDistances(
        page.listings.map((l) => l.toCropListing()).toList(),
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _listings = crops;
        _page = page.currentPage < 1 ? 1 : page.currentPage;
        _lastPage = page.lastPage < _page ? _page : page.lastPage;
        _loadMoreError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Appends the next page under the cards already on screen.
  ///
  /// Never touches [_isLoading]: a spinner over the whole feed while page two
  /// arrives is the exact behaviour paging was added to remove.
  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    final nextPage = _page + 1;

    try {
      final page = await _feed.fetchFeedPage(
        page: nextPage,
        perPage: _pageSize,
        category: _filters.categoryId,
        availability: _filters.availability?.wireValue,
sort: _filters.sort,
        // Ranking and an explicit ordering are two answers to the same
        // question, and the backend can only give one. Asking for the ranked
        // feed when the buyer picked "soonest harvest" would leave the sheet
        // showing an order the feed is not in, so the chosen sort wins and the
        // ranking is simply not asked for.
        personalized: _filters.sort == HomeSortMode.latest,
      );

      final crops = await _resolveDistances(
        page.listings.map((l) => l.toCropListing()).toList(),
      );
      if (!mounted) return;

      setState(() {
        _listings = _appendWithoutDuplicates(_listings, crops);
        // Trust the page that actually came back, not the one that was asked
        // for: a server that clamps the request would otherwise advance the
        // counter past content it never sent.
        _page = page.currentPage < nextPage ? nextPage : page.currentPage;
        _lastPage = page.lastPage < _page ? _page : page.lastPage;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _loadMoreError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Concatenates two pages, dropping anything already on screen.
  ///
  /// Ranking is not stable across requests — a contact or a review between two
  /// page fetches moves a listing up one — so the same row can legitimately
  /// appear on two pages. Appending it would render the same card twice, and
  /// the duplicate would carry the same listing id, so tapping either opens the
  /// same thing twice. Rows without an id cannot be compared and are kept.
  static List<CropListing> _appendWithoutDuplicates(
    List<CropListing> existing,
    List<CropListing> incoming,
  ) {
    if (incoming.isEmpty) return existing;

    final seen = <String>{
      for (final l in existing)
        if (l.listingId != null && l.listingId!.isNotEmpty) l.listingId!,
    };

    final fresh = incoming.where((l) {
      final id = l.listingId;
      if (id == null || id.isEmpty) return true;
      return seen.add(id);
    }).toList();

    if (fresh.isEmpty) return existing;
    return [...existing, ...fresh];
  }

  /// Pull-to-refresh: reload page one while keeping current content on screen.
  Future<void> _refresh() async {
    // Farms and the buyer's position are re-read: a pull-to-refresh is also the
    // buyer saying "something changed", and a farm that moved or appeared since
    // the last load is exactly the kind of change it should pick up.
    _distanceLookupDone = false;
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
  ///
  /// The lookup is remembered for the life of one feed load, including when it
  /// fails. Retrying on every page would mean every appended page re-asks a
  /// question that just came back "no", on a screen that has already moved on.
  Future<List<CropListing>> _resolveDistances(
    List<CropListing> listings,
  ) async {
    if (!_distanceLookupDone) {
      _distanceLookupDone = true;
      try {
        _farms = await FarmService.fetchPublicFarms();
        _buyerPosition = await LocationService.defaultBuyerPosition();
      } catch (_) {
        _farms = [];
        _buyerPosition = null;
      }
    }

    final you = _buyerPosition;
    if (_farms.isEmpty || you == null) return listings;

    final byId = {for (final f in _farms) f.id: f};
    return listings.map((l) {
      final farm = l.farmId == null ? null : byId[l.farmId];
      if (farm == null) return l;
      final km = LocationService.distanceKm(
        you,
        LatLng(farm.latitude, farm.longitude),
      );
      return l.withDistance(LocationService.distanceLabel(km));
    }).toList();
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
                    // A CustomScrollView rather than a scroll view around a
                    // Column: the Column lays out and builds every card the
                    // moment the feed arrives, which is the cost paging exists
                    // to remove. Slivers build what is on screen.
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          sliver: SliverToBoxAdapter(
                            child: _buildSectionTitle(),
                          ),
                        ),
                        ..._buildFeedSlivers(),
                      ],
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

    // Category and availability are the server's job now, so either one
    // changing means the whole feed has to come back. Sort alone does not —
    // except for `latest`, which is the ranked default rather than a real
    // ordering, so moving off it (or back onto it) changes what the server
    // ranks and does need a fresh request.
    final mustRefetch =
        picked.needsRefetch ||
        picked.sort != _filters.sort ||
        (picked.sort == HomeSortMode.latest) !=
            (_filters.sort == HomeSortMode.latest);

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

  /// The feed itself, in whichever of its four states it currently is.
  ///
  /// Returning a list rather than one widget is what lets the cards and the
  /// "loading more" footer be siblings in the same viewport — the footer has to
  /// sit below the last card, not inside a column that the cards also live in.
  List<Widget> _buildFeedSlivers() {
    // First load. Skeletons rather than a spinner: the feed keeps its shape,
    // so when the real cards replace them nothing jumps.
    if (_isLoading) {
      return const [
        SliverToBoxAdapter(child: CropLadderSkeleton()),
        SliverToBoxAdapter(child: SizedBox(height: 24)),
      ];
    }

    if (_errorMessage != null) {
      return [
        SliverToBoxAdapter(child: _buildFeedError()),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ];
    }

    final listings = _filteredListings;

    if (listings.isEmpty) {
      return const [
        SliverToBoxAdapter(child: SizedBox(height: 120)),
        SliverToBoxAdapter(child: _EmptyFeedState()),
        SliverToBoxAdapter(child: SizedBox(height: 24)),
      ];
    }

    return [
      CropLadderSliver(listings: listings, onTap: _openDetail),
      SliverToBoxAdapter(child: _buildFeedFooter()),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  /// Below the cards: the append spinner, a retry after a failed page, or
  /// nothing at all.
  ///
  /// Silence when idle is deliberate. A persistent "no more posts" line costs a
  /// row of screen for information the buyer learns by scrolling.
  Widget _buildFeedFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: FarmSpotLoader(size: 28)),
      );
    }

    if (_loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              _loadMoreError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            TextButton(onPressed: _loadMore, child: const Text('Try again')),
          ],
        ),
      );
    }

    return const SizedBox(height: 8);
  }

  Widget _buildFeedError() {
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
}

/// Says the feed is empty rather than leaving a blank screen below the
/// heading, which is indistinguishable from a still-loading feed once the
/// spinner is gone.
class _EmptyFeedState extends StatelessWidget {
  const _EmptyFeedState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Text(
          'No crops match these filters yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      ),
    );
  }
}
