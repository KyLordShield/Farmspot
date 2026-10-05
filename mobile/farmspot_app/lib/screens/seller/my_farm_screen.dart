import 'package:flutter/material.dart';

import '../../models/farm_setup_data.dart';
import '../../models/farm_stats.dart';
import '../../models/listing.dart';
import '../../models/my_farm_listing_page.dart';
import '../../services/farm_service.dart';
import '../../services/listing_service.dart';
import '../../services/my_farm_listings_service.dart';
import '../../theme.dart';
import '../../widgets/farmspot_loader.dart';
import '../../widgets/my_farm_widgets.dart';
import '../../widgets/seller_widgets.dart';
import '../../widgets/stat_box.dart';
import '../all_reviews_screen.dart';
import '../home_screen.dart';
import '../insights_screen.dart';
import '../map_screen.dart';
import '../profile_screen.dart';
import 'add_crop_screen.dart';
import 'edit_farm_screen.dart';
import 'farm_setup_details_screen.dart';

class MyFarmScreen extends StatefulWidget {
  /// Injectable so the paging behaviour can be tested without a server. Omitted
  /// in the app, where the real endpoint is used.
  final MyFarmListingsGateway? gateway;

  const MyFarmScreen({super.key, this.gateway});

  @override
  State<MyFarmScreen> createState() => _MyFarmScreenState();
}

class _MyFarmScreenState extends State<MyFarmScreen> {
  /// How many rows each request asks for. Also the server's default, but sent
  /// explicitly: the endpoint only paginates a caller that asks, so leaving it
  /// off would ask for the whole list again.
  static const int _perPage = 10;

  /// Scroll listener for infinite loading. Two widgets' worth of rows below the
  /// viewport, so a fast scroll or a short final page still triggers the load
  /// before the seller reaches the bottom.
  static const double _loadMoreThreshold = 400;

  /// LST_AVAILABILITY values that mean an admin took the listing off sale.
  ///
  /// `REMOVED` is the removal flag; `NOT_AVAILABLE` here is the moderation value,
  /// which is a different column from LST_STATUS even though a farmer may also
  /// pick `NOT_AVAILABLE` there. Only the seller's own row claims
  /// "Hidden by admin", and a farmer who chose the status never gets the chip.
  static const Set<String> _adminHiddenAvailability = {
    'REMOVED',
    'NOT_AVAILABLE',
  };

  late final MyFarmListingsGateway _gateway =
      widget.gateway ?? MyFarmListingsService.instance;

  final ScrollController _scrollController = ScrollController();

  bool _farmsLoading = true;

  /// Every operational farm the seller owns. A seller may run several, so this
  /// is a list and [_selectedFarmId] says which one the screen is showing.
  List<Map<String, dynamic>> _farms = [];
  String? _selectedFarmId;

  /// True while the remove request is in flight, so the action cannot be
  /// tapped twice and the row can show progress.
  bool _removingFarm = false;

  /// The farm currently being displayed, or null before the first load or when
  /// the seller has none.
  Map<String, dynamic>? get _farm {
    if (_selectedFarmId == null) return null;
    for (final farm in _farms) {
      if (farm['FRM_ID'] == _selectedFarmId) return farm;
    }
    return null;
  }

  /// Farm-owner performance totals (profile views / buyer contacts / active
  /// listings) from GET /api/farms/{id}/stats. Null while loading or on
  /// failure, so the boxes show "—" instead of flashing a misleading '0'.
  FarmStats? _stats;

  // ---------------------------------------------------------------------------
  // Listings: paged, server-filtered, never filtered on the client.
  //
  // Every field below the farms block exists because paging moved the work to
  // the server. The screen keeps one accumulated row list and the paging
  // position; it does not decide what belongs in the list, and it does not count
  // the rows it happens to hold.
  // ---------------------------------------------------------------------------

  /// Rows loaded so far, across every page fetched. Order is the server's.
  List<Listing> _listings = [];

  /// Farm-wide totals for the summary card and the filter chip counts, straight
  /// from the server. Never derived from [_listings]: a page of ten out of forty
  /// listings would otherwise report ten.
  MyFarmSummary _summary = MyFarmSummary.empty;

  /// The active status filter. Applied server-side, so changing it refetches
  /// from page 1 rather than re-filtering what is loaded — a client-side filter
  /// would silently drop the rows still on other pages.
  MyFarmStatusFilter _filter = MyFarmStatusFilter.all;

  int _currentPage = 1;
  int _lastPage = 1;

  /// True only for the very first load, when there are no rows to show behind
  /// it. A filter change with rows already on screen shows those rows plus a
  /// thin progress bar instead of blanking the screen.
  bool _initialLoading = true;

  /// True while a later page is in flight, so the trailing loader shows and the
  /// same page is never requested twice from overlapping scroll events.
  bool _loadingMore = false;

  /// Failure of the first page with no rows to fall back on: the screen shows
  /// this with a Retry instead of a list.
  String? _loadError;

  /// Failure of a later page. The rows already loaded stay exactly where they
  /// are and the retry sits under them — a seller part way down the list should
  /// not lose it to a dropped connection.
  String? _pageError;

  /// LST_ID of the listing currently having its status updated (for per-row
  /// loading/disabled affordance).
  String? _updatingId;

  /// Incremented on every reset so a response for an abandoned query — the
  /// seller's old farm, a filter they have already changed away from — is
  /// discarded instead of landing in the list.
  int _generation = 0;

  bool get _hasMore => _currentPage < _lastPage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Farms first, then listings.
  ///
  /// The order matters and was the reason this screen had to change at all:
  /// listings are now requested with a `farm_id`, so the selected farm has to be
  /// resolved before the first request. Loading them in parallel would fetch
  /// every farm's listings and then throw most of them away.
  Future<void> _bootstrap() async {
    await _loadFarm();
    if (!mounted) return;
    await _loadListings(reset: true);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreThreshold) return;
    _loadListings();
  }

  Future<void> _loadFarm() async {
    final farms = await FarmService.getFarms();
    if (!mounted) return;

    // Keep the seller's current farm selected across a refresh; otherwise fall
    // back to the first, which getFarms() orders APPROVED-first.
    final previousId = _selectedFarmId;
    final stillExists = farms.any((f) => f['FRM_ID'] == previousId);
    final selectedId = stillExists
        ? previousId
        : (farms.isNotEmpty ? farms.first['FRM_ID'] as String? : null);

    setState(() {
      _farmsLoading = false;
      _farms = farms;
      _selectedFarmId = selectedId;
    });

    // Stats belong to one farm, so they reload whenever the selection changes.
    await _loadStats();
  }

  Future<void> _loadStats() async {
    final farmId = _selectedFarmId;
    if (farmId == null) {
      if (mounted) setState(() => _stats = null);
      return;
    }
    try {
      final stats = await FarmService.fetchFarmStats(farmId);
      if (!mounted) return;
      // A slow response for a farm the seller has since navigated away from
      // must not overwrite the new farm's numbers.
      if (_selectedFarmId != farmId) return;
      setState(() => _stats = stats);
    } catch (_) {
      // Stats are supplementary — a failure keeps "—" and never breaks the screen.
      if (!mounted) return;
      if (_selectedFarmId != farmId) return;
      setState(() => _stats = null);
    }
  }

  /// Switches the whole screen to another farm: card, stats and listings all
  /// follow, because every panel is scoped to the selected farm.
  Future<void> _selectFarm(String farmId) async {
    if (_selectedFarmId == farmId) return;
    setState(() {
      _selectedFarmId = farmId;
      _stats = null;
    });
    await _loadStats();
    // The loaded rows belong to the farm the seller just left, so they go back
    // to page 1 of the new one instead of being filtered down: a farm can have
    // more rows than the first page holds.
    await _loadListings(reset: true);
  }

  /// Applies a status filter, refetching from page 1.
  ///
  /// The counts on the chips come from the last response and are not filtered
  /// either, so the seller can always see what selecting another chip would
  /// bring in — and the chip they are on is visibly the active one.
  Future<void> _applyFilter(MyFarmStatusFilter filter) async {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    await _loadListings(reset: true);
    _scrollToTop();
  }

  /// Pull-to-refresh: reloads the farm card, its stats, and the listings.
  Future<void> _refresh() async {
    await _loadFarm();
    if (!mounted) return;
    await _loadListings(reset: true);
  }

  /// Opens the farm editor. Pops true after a successful save — reload the
  /// farm card (name/description) so the changes show up immediately, and the
  /// stats stay in sync with the refreshed farm.
  Future<void> _openEditFarm() async {
    final farmId = _farm?['FRM_ID'] as String?;
    if (farmId == null) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditFarmScreen(farmId: farmId)),
    );
    if (saved == true && mounted) {
      await _refresh();
    }
  }

  /// Fetches one page of listings.
  ///
  /// [reset] starts over from page 1 (first load, refresh, farm switch, filter
  /// change). Without it the next page is appended.
  ///
  /// Three things this method is careful about, all of them the failure modes of
  /// a scroll-driven list:
  ///   * the same page is never requested twice — an overlapping scroll event or
  ///     a double tap on Retry while the first request is still open returns
  ///     early instead of duplicating rows;
  ///   * rows are merged by LST_ID, so a row that arrives twice (two pages that
  ///     overlap because a listing was added between them) appears once;
  ///   * a superseded response is dropped, so a slow page-1 reply cannot land on
  ///     top of a filter change that has already replaced the list.
  Future<void> _loadListings({bool reset = false}) async {
    if (!reset) {
      // End-of-list is terminal: without this, a short final page would ask for
      // another one on every scroll event and get an empty list back each time.
      if (_loadingMore || _pageError != null || !_hasMore) return;
      // While page 1 is still in flight the list is empty, so its scroll extent
      // is near zero and "am I at the bottom?" is trivially true. Without this
      // guard the first load asks for page 1 twice — and a second reset-free
      // request would land on top of the first with the same rows, before the
      // screen had a single row to show.
      if (_initialLoading) return;
    }

    final generation = reset ? ++_generation : _generation;
    final page = reset ? 1 : _currentPage + 1;

    if (reset) {
      _pageError = null;
      if (_listings.isEmpty) setState(() => _initialLoading = true);
      setState(() {});
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final result = await _gateway.fetch(
        page: page,
        perPage: _perPage,
        farmId: _selectedFarmId,
        status: _filter,
      );
      if (!mounted || generation != _generation) return;

      setState(() {
        _initialLoading = false;
        _loadingMore = false;
        _loadError = null;
        _pageError = null;
        _currentPage = result.currentPage;
        _lastPage = result.lastPage;
        _summary = result.summary;

        final merged = reset ? <Listing>[] : List<Listing>.from(_listings);
        final seen = merged.map((l) => l.id).toSet();
        for (final listing in result.listings) {
          if (seen.add(listing.id)) merged.add(listing);
        }
        _listings = merged;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;

      setState(() {
        _loadingMore = false;
        _initialLoading = false;
        // Rows already on screen are never discarded by a failure — only a
        // first load with nothing to show becomes an error state.
        if (_listings.isEmpty) {
          _loadError = _friendlyError(e);
        } else {
          _pageError = _friendlyError(e);
        }
      });
    }
  }

  /// Retries whichever request failed.
  Future<void> _retry({required bool isTrailing}) async {
    if (isTrailing) {
      // The retry under a loaded page asks for that same page again. The stored
      // error has to go first: _loadListings refuses to append while one is set,
      // which is what stops a scroll event re-requesting a page that already
      // failed. Clearing it here is what makes the button do anything at all.
      setState(() => _pageError = null);
      await _loadListings();
      return;
    }
    await _loadListings(reset: true);
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  /// Starts the add-another-farm wizard. Documents are optional on this path
  /// because the seller's ID and permit are already on file from their first
  /// farm — the server copies them onto the new farm.
  Future<void> _addFarm() async {
    // Snapshotted from the farms already on screen so the one that appears
    // afterwards is the farm the seller just made. Picking `farms.last` would
    // not do: getFarms() sorts APPROVED farms first, so a brand-new
    // PENDING_REVIEW farm would land behind an older approved one.
    final before = _farms
        .map((f) => f['FRM_ID'] as String?)
        .whereType<String>()
        .toSet();

    await Navigator.of(context).push(
      MaterialPageRoute(
        // Starts at step 1, not the identity step: every farm needs its own
        // name, description, barangay and photos even when the seller's
        // documents are already on file from their first farm.
        builder: (_) => FarmSetupDetailsScreen(
          farmSetupData: FarmSetupData(),
          isAdditionalFarm: true,
        ),
      ),
    );
    if (!mounted) return;

    final farms = await FarmService.getFarms();
    if (!mounted) return;

    final created = farms.firstWhere(
      (f) => !before.contains(f['FRM_ID']),
      orElse: () => const {},
    );
    final createdId = created['FRM_ID'] as String?;

    setState(() {
      _farms = farms;
      _farmsLoading = false;
      if (createdId != null) {
        _selectedFarmId = createdId;
        // The old farm's totals must not sit above the new farm's listings.
        _stats = null;
      }
    });
    if (createdId != null) await _loadStats();
    if (!mounted) return;
    await _loadListings(reset: true);
  }

  /// Removes the farm currently on screen, after an explicit confirmation.
  ///
  /// Only offered when the seller has more than one farm: the last farm is
  /// what keeps the account selling, so it is protected. A seller who wants to
  /// stop entirely deactivates their seller account instead, which is the flow
  /// that resets the seller flags.
  ///
  /// The server archives rather than deletes, so the farm disappears from the
  /// map and this list while its listings and buyer conversations are kept.
  Future<void> _removeSelectedFarm() async {
    final farmId = _selectedFarmId;
    final farm = _farm;
    if (farmId == null || farm == null) return;

    // Guarded in the UI so the action never appears when it would be refused,
    // but the server re-checks: this is a rule about the data, not the widget.
    if (_farms.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You cannot remove your only farm. Deactivate your seller account '
            'instead if you no longer want to sell.',
          ),
        ),
      );
      return;
    }

    final name = farm['FRM_NAME'] as String? ?? 'This farm';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
          'It will stop appearing on the map and in your farm list, and its '
          'crops will be taken off sale.\n\n'
          'Your buyers\' conversations about this farm are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingFarm = true);
    try {
      await FarmService.removeFarm(farmId);
      if (!mounted) return;

      final farms = await FarmService.getFarms();
      if (!mounted) return;

      setState(() {
        _farms = farms;
        _removingFarm = false;
        // Move the selection off the farm that was just removed, otherwise the
        // card would keep rendering a farm that is no longer in the list.
        if (!farms.any((f) => f['FRM_ID'] == _selectedFarmId)) {
          _selectedFarmId = farms.isEmpty
              ? null
              : farms.first['FRM_ID'] as String?;
          _stats = null;
        }
      });
      if (_selectedFarmId != null) await _loadStats();
      if (!mounted) return;
      // The removed farm's listings are gone from the seller's view; refetch so
      // the rows do not linger as a list the server no longer backs.
      await _loadListings(reset: true);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$name" removed.')));
    } on FarmRemovalBlocked catch (e) {
      if (!mounted) return;
      setState(() => _removingFarm = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _removingFarm = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  Future<void> _addCrop() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        // Listings are created against a specific farm, so a seller with
        // several must list on the one currently on screen.
        builder: (_) =>
            AddCropScreen(isFirstCrop: false, farmId: _selectedFarmId),
      ),
    );
    // AddCropScreen pops true after creating the listing — refresh so the new
    // listing appears in this list without a full screen reload.
    if (added == true && mounted) {
      await _loadListings(reset: true);
    }
  }

  Future<void> _openStatusPicker(Listing listing) async {
    final current = listing.status;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Change status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text('How should buyers see this crop?'),
            ),
            _statusSheetTile(
              ctx,
              'AVAILABLE_NOW',
              'Available Now',
              'Ready for buyers to contact you',
              Icons.check_circle_outline,
              selected: current == 'AVAILABLE_NOW',
            ),
            _statusSheetTile(
              ctx,
              'SOON_TO_HARVEST',
              'Soon to Harvest',
              "Let buyers know it's coming",
              Icons.schedule,
              selected: current == 'SOON_TO_HARVEST',
            ),
            _statusSheetTile(
              ctx,
              'NOT_AVAILABLE',
              'Not Available',
              'Hidden from marketplace',
              Icons.bedtime_outlined,
              selected: current == 'NOT_AVAILABLE',
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    await _changeStatus(listing, picked);
  }

  Widget _statusSheetTile(
    BuildContext ctx,
    String value,
    String title,
    String subtitle,
    IconData icon, {
    required bool selected,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? AppColors.primaryGreen : Colors.black45,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppColors.primaryGreen)
          : null,
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  Future<void> _changeStatus(Listing listing, String status) async {
    setState(() => _updatingId = listing.id);
    try {
      await ListingService.updateListingStatus(
        listingId: listing.id,
        status: status,
      );
      if (!mounted) return;
      setState(() => _updatingId = null);
      // Refetch rather than patching the row in place. Every status update also
      // moves the expiry date, which can move the listing between the Active
      // and Expired buckets — and those counts come from the server, so a
      // locally patched row would sit next to a summary that no longer matches
      // it.
      await _loadListings(reset: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingId = null);
      // Keep the previous state; just tell the user it failed.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  /// Renews an expired listing by re-sending the status it already has.
  ///
  /// The endpoint resets LST_EXPIRY_DATE on any status update, so this is the
  /// whole of "renew". It deliberately does not force AVAILABLE_NOW: a seller
  /// whose crop has not come back yet should keep SOON_TO_HARVEST and get the
  /// extra three days, rather than be listed as buyable because they pressed a
  /// button about the expiry.
  Future<void> _renew(Listing listing) async {
    await _changeStatus(listing, listing.status);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listing renewed for another 3 days.')),
    );
  }

  /// Opens the existing read-only reviews screen for this listing.
  ///
  /// Nothing is added to make it read-only: the screen already shows write
  /// controls only when the server says `can_review`, and the server has
  /// always answered false for the seller's own listing. Reusing it as-is means
  /// a seller reads exactly the list a buyer reads, with no second implementation
  /// that could disagree with it.
  Future<void> _openReviews(Listing listing) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AllReviewsScreen(
          listingId: listing.id,
          cropName: listing.cropIcon ?? listing.categoryName ?? 'Crop',
        ),
      ),
    );
  }

  /// Full edit entry point (edit mode of AddCropScreen). Pops true after a
  /// successful save — refresh so the label/status/photo changes show up.
  Future<void> _openEditCrop(Listing listing) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddCropScreen(existingListing: listing),
      ),
    );
    if (saved == true && mounted) {
      await _loadListings(reset: true);
    }
  }

  /// Deletes the listing after an explicit confirmation, then refreshes the
  /// list so the tile disappears (same post-change refresh used by add/edit).
  Future<void> _deleteListing(Listing listing) async {
    final label = listing.cropIcon ?? listing.categoryName ?? 'Crop';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete crop?'),
        content: Text('"$label" will be permanently removed from your farm.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ListingService.deleteListing(listing.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$label" deleted.')));
      await _loadListings(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  /// Derives the owner-only view of one listing from its wire fields.
  ListingOwnerState _ownerState(Listing listing) {
    final availability = (listing.availability ?? '').toUpperCase();
    return ListingOwnerState(
      listing: listing,
      hiddenByAdmin: _adminHiddenAvailability.contains(availability),
    );
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  void _handleNavTap(int i) {
    if (i == 3) return; // already on My Farm
    switch (i) {
      case 0:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        break;
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
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: _buildFarmSection()),
                    SliverToBoxAdapter(child: _buildListingsHeader()),
                    ..._buildListSlivers(),
                    SliverToBoxAdapter(child: _buildFooter()),
                  ],
                ),
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

  /// Farm switcher, farm card and performance boxes. One sliver rather than
  /// three so the spacing between them cannot drift.
  Widget _buildFarmSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          _buildFarmSwitcher(),
          const SizedBox(height: 12),
          _buildFarmCard(),
          const SizedBox(height: 20),
          _buildStatsRow(),
        ],
      ),
    );
  }

  /// "Listings / Add Crop", the ratings summary and the filter row.
  Widget _buildListingsHeader() {
    // The count is the farm's total, not the rows loaded: on page 1 of three the
    // label must not claim the list is a tenth as big as it is.
    final total = _summary.totalListings;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                total == 1 ? 'Listing' : 'Listings',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: _addCrop,
                icon: const Icon(
                  Icons.add,
                  size: 16,
                  color: AppColors.primaryGreen,
                ),
                label: const Text(
                  'Add Crop',
                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MyFarmSummaryCard(summary: _summary),
          const SizedBox(height: 12),
          MyFarmFilterRow(
            active: _filter,
            summary: _summary,
            onChanged: _applyFilter,
          ),
          const SizedBox(height: 12),
          // A thin bar instead of a blank list when refetching with rows already
          // on screen, so a filter change never looks like an empty farm.
          if (_listings.isNotEmpty && _loadError == null)
            LinearProgressIndicator(
              minHeight: 2,
              value: _initialLoading ? null : 0,
              backgroundColor: Colors.transparent,
            )
          else
            const SizedBox(height: 2),
        ],
      ),
    );
  }

  /// The rows themselves, plus whatever belongs under them.
  ///
  /// SliverList, not a Column of every row: a seller with forty listings must
  /// not build forty thumbnails to scroll past two of them. Only the loaded
  /// pages are ever built, and the trailing loader and retry ride in the same
  /// lazy list so a long page does not need its own scrollable.
  List<Widget> _buildListSlivers() {
    if (_initialLoading && _listings.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: FarmSpotLoader(size: 64),
          ),
        ),
      ];
    }

    if (_loadError != null && _listings.isEmpty) {
      return [SliverToBoxAdapter(child: _buildErrorState(_loadError!))];
    }

    if (_listings.isEmpty) {
      return [SliverToBoxAdapter(child: _buildEmptyState())];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _buildRow(_listings[i]),
            childCount: _listings.length,
          ),
        ),
      ),
      SliverToBoxAdapter(child: _buildListFooter()),
    ];
  }

  Widget _buildRow(Listing listing) {
    return MyFarmListingRow(
      key: ValueKey(listing.id),
      listing: listing,
      state: _ownerState(listing),
      updating: _updatingId == listing.id,
      onStatusTap: () => _openStatusPicker(listing),
      onRenewTap: () => _renew(listing),
      onReviewsTap: () => _openReviews(listing),
      onEditTap: () => _openEditCrop(listing),
      onDeleteTap: () => _deleteListing(listing),
    );
  }

  /// Under the last row: a failed next page with its retry, the page loader, or
  /// nothing at all when the whole list is loaded.
  Widget _buildListFooter() {
    if (_pageError != null) {
      return _buildErrorState(_pageError!, isTrailing: true);
    }
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }

  Widget _buildErrorState(String message, {bool isTrailing = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isTrailing ? 8 : 20),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _retry(isTrailing: isTrailing),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final farmName = _farm?['FRM_NAME'] as String?;

    // Under a filter, "no crops yet" would be a lie: the seller has crops, just
    // not in this bucket. The message has to name the filter, or an empty
    // Expired chip looks like data loss.
    if (_filter != MyFarmStatusFilter.all) {
      final label = _filter.label.toLowerCase();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text(
            _summary.countFor(_filter) == 0
                ? 'You have no $label listings right now.'
                : 'Nothing in $label yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Text(
          farmName == null
              ? 'No crops listed yet. Tap "Add Crop" to get started.'
              : 'Nothing listed on $farmName yet. Tap "Add Crop" to get started.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// "Remove this farm", shown only when there is more than one farm to choose
  /// from. With a single farm the action would be refused anyway, so it is
  /// hidden rather than shown disabled — the seller is not invited to press a
  /// button that cannot work. Going fully inactive is the Profile screen's
  /// "Deactivate seller" action.
  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          _buildRemoveFarmAction(),
          if (!_initialLoading && _listings.isEmpty)
            // Keeps an empty farm scrollable so pull-to-refresh still works.
            const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      color: AppColors.primaryGreen,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'My Farm',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          // A seller can run more than one farm, so there is always a way to
          // start another from the screen that lists them.
          TextButton.icon(
            onPressed: _addFarm,
            icon: const Icon(
              Icons.add_home_work,
              size: 16,
              color: Colors.white,
            ),
            label: const Text(
              'Add Farm',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ],
      ),
    );
  }

  /// Lets the seller move between their farms. Only shown when there is more
  /// than one — with a single farm a picker would just be noise.
  Widget _buildFarmSwitcher() {
    if (_farmsLoading || _farms.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _farms.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final farm = _farms[i];
          final id = farm['FRM_ID'] as String?;
          final name = farm['FRM_NAME'] as String? ?? 'Farm';
          final selected = id == _selectedFarmId;
          final pending = farm['FRM_STATUS'] == 'PENDING_REVIEW';

          return GestureDetector(
            onTap: () => _selectFarm(id!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryGreen : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? AppColors.primaryGreen : Colors.black12,
                ),
              ),
              child: Row(
                children: [
                  if (pending) ...[
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: selected ? Colors.white : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFarmCard() {
    if (_farmsLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF6EC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return FarmCard(
      name: _farm?['FRM_NAME'] as String? ?? '',
      // Location is locked post-approval; shown read-only and never editable.
      barangay: _farm?['FRM_BARANGAY'] as String? ?? '',
      status: _farm?['FRM_STATUS'] as String? ?? '',
      onEditTap: _openEditFarm,
    );
  }

  /// Farm-owner performance boxes (Profile Views / Buyer Contacts / Active
  /// Listings). Values stay "—" while the stats fetch is in flight or failed —
  /// never a misleading '0' (mirrors the old Profile stats-row behavior).
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: StatBox(
            label: 'Profile Views',
            value: _stats?.profileViews.toString() ?? '—',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatBox(
            label: 'Buyer Contacts',
            value: _stats?.buyerContacts.toString() ?? '—',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatBox(
            label: 'Active Listings',
            value: _stats?.activeListings.toString() ?? '—',
          ),
        ),
      ],
    );
  }

  Widget _buildRemoveFarmAction() {
    if (_farmsLoading || _farms.length < 2 || _farm == null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _removingFarm ? null : _removeSelectedFarm,
        icon: _removingFarm
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_outline, size: 16),
        label: const Text(
          'Remove this farm',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
      ),
    );
  }
}
