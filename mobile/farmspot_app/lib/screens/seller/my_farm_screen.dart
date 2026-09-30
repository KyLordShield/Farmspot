import 'package:flutter/material.dart';

import '../../models/farm_setup_data.dart';
import '../../models/farm_stats.dart';
import '../../models/listing.dart';
import '../../services/farm_service.dart';
import '../../services/listing_service.dart';
import '../../theme.dart';
import '../../widgets/seller_widgets.dart';
import '../../widgets/farmspot_loader.dart';
import '../../widgets/stat_box.dart';
import '../insights_screen.dart';
import '../map_screen.dart';
import '../profile_screen.dart';
import '../home_screen.dart';
import 'add_crop_screen.dart';
import 'edit_farm_screen.dart';
import 'farm_setup_details_screen.dart';

class MyFarmScreen extends StatefulWidget {
  const MyFarmScreen({super.key});

  @override
  State<MyFarmScreen> createState() => _MyFarmScreenState();
}

class _MyFarmScreenState extends State<MyFarmScreen> {
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

  bool _listingsLoading = true;

  /// All of the seller's listings. Filtered down to the selected farm for
  /// display, because listings belong to a farm, not to the account.
  List<Listing> _allListings = [];
  String? _listingsError;

  /// LST_ID of the listing currently having its status updated (for per-tile
  /// loading/disabled affordance).
  String? _updatingId;

  /// Listings belonging to the farm on screen.
  List<Listing> get _listings => _allListings
      .where((l) => _selectedFarmId == null || l.farmId == _selectedFarmId)
      .toList();

  @override
  void initState() {
    super.initState();
    _loadFarm();
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
  }

  /// Pull-to-refresh: reloads the farm card, its stats, and the listings.
  Future<void> _refresh() async {
    await _loadFarm();
    await _loadListings(showLoading: false);
  }

  /// Opens the farm editor. Pops true after a successful save — reload the
  /// farm card (name/description) so the changes show up immediately, and the
  /// stats stay in sync with the refreshed farm.
  Future<void> _openEditFarm() async {
    final farmId = _farm?['FRM_ID'] as String?;
    if (farmId == null) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditFarmScreen(farmId: farmId),
      ),
    );
    if (saved == true && mounted) {
      await _loadFarm();
      await _loadListings(showLoading: false);
    }
  }

  Future<void> _loadListings({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _listingsLoading = true);
    }
    try {
      final listings = await ListingService.fetchMyListings();
      if (!mounted) return;
      setState(() {
        _listingsLoading = false;
        _listingsError = null;
        _allListings = listings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listingsLoading = false;
        _listingsError = _friendlyError(e);
      });
    }
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
          _selectedFarmId = farms.isEmpty ? null : farms.first['FRM_ID'] as String?;
          _stats = null;
        }
      });
      if (_selectedFarmId != null) await _loadStats();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" removed.')),
      );
    } on FarmRemovalBlocked catch (e) {
      if (!mounted) return;
      setState(() => _removingFarm = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _removingFarm = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
  }

  Future<void> _addCrop() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        // Listings are created against a specific farm, so a seller with
        // several must list on the one currently on screen.
        builder: (_) => AddCropScreen(
          isFirstCrop: false,
          farmId: _selectedFarmId,
        ),
      ),
    );
    // AddCropScreen pops true after creating the listing — refresh so the new
    // listing appears in this list without a full screen reload.
    if (added == true && mounted) {
      await _loadListings(showLoading: false);
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
      leading: Icon(icon,
          color: selected ? AppColors.primaryGreen : Colors.black45),
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
      final updated = await ListingService.updateListingStatus(
        listingId: listing.id,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _updatingId = null;
        final index = _allListings.indexWhere((l) => l.id == listing.id);
        if (index != -1) {
          _allListings[index] = updated;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingId = null);
      // Keep the previous state; just tell the user it failed.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
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
      await _loadListings(showLoading: false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$label" deleted.')),
      );
      await _loadListings(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
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
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildFarmSwitcher(),
                    const SizedBox(height: 12),
                    _buildFarmCard(),
                    const SizedBox(height: 20),
                    _buildStatsRow(),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _listings.length == 1 ? 'Listing' : 'Listings',
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
                    _buildListingsArea(),
                    const SizedBox(height: 8),
                    _buildRemoveFarmAction(),
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

  /// "Remove this farm", shown only when there is more than one farm to choose
  /// from. With a single farm the action would be refused anyway, so it is
  /// hidden rather than shown disabled — the seller is not invited to press a
  /// button that cannot work. Going fully inactive is the Profile screen's
  /// "Deactivate seller" action.
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
            icon: const Icon(Icons.add_home_work, size: 16, color: Colors.white),
            label: const Text(
              'Add Farm',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

  Widget _buildListingsArea() {
    if (_listingsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: FarmSpotLoader(size: 64),
      );
    }

    if (_listingsError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              _listingsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _loadListings(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_listings.isEmpty) {
      final farmName = _farm?['FRM_NAME'] as String?;
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

    return Column(
      children: [
        for (final listing in _listings)
          CropListTile(
            listing: listing,
            updating: _updatingId == listing.id,
            onStatusTap: () => _openStatusPicker(listing),
            onEditTap: () => _openEditCrop(listing),
            onDeleteTap: () => _deleteListing(listing),
          ),
      ],
    );
  }
}