import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../../services/farm_service.dart';
import '../../services/listing_service.dart';
import '../../theme.dart';
import '../../widgets/seller_widgets.dart';
import '../insights_screen.dart';
import '../map_screen.dart';
import '../profile_screen.dart';
import '../home_screen.dart';
import 'add_crop_screen.dart';

class MyFarmScreen extends StatefulWidget {
  const MyFarmScreen({super.key});

  @override
  State<MyFarmScreen> createState() => _MyFarmScreenState();
}

class _MyFarmScreenState extends State<MyFarmScreen> {
  bool _farmsLoading = true;
  Map<String, dynamic>? _farm;

  bool _listingsLoading = true;
  List<Listing> _listings = [];
  String? _listingsError;

  /// LST_ID of the listing currently having its status updated (for per-tile
  /// loading/disabled affordance).
  String? _updatingId;

  @override
  void initState() {
    super.initState();
    _loadFarm();
    _loadListings();
  }

  Future<void> _loadFarm() async {
    final farms = await FarmService.getFarms();
    if (!mounted) return;
    setState(() {
      _farmsLoading = false;
      // "One active farm" convention — the first farm returned is the farm.
      _farm = farms.isNotEmpty ? farms.first : null;
    });
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
        _listings = listings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listingsLoading = false;
        _listingsError = _friendlyError(e);
      });
    }
  }

  Future<void> _addCrop() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const AddCropScreen(isFirstCrop: false),
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
        final index = _listings.indexWhere((l) => l.id == listing.id);
        if (index != -1) {
          _listings[index] = updated;
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
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFarmCard(),
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
                  _buildListingsArea(),
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

    final name = _farm?['FRM_NAME'] as String? ?? '';
    final barangay = _farm?['FRM_BARANGAY'] as String? ?? '';
    final badge = _buildStatusBadge();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryGreen,
            child: Icon(Icons.agriculture, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Your Farm' : name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  barangay.isEmpty ? 'Farm location' : barangay,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          ?badge,
        ],
      ),
    );
  }

  /// "Live" only when the farm is APPROVED; otherwise show an appropriate
  /// label (Pending Review) or nothing at all.
  Widget? _buildStatusBadge() {
    final status = _farm?['FRM_STATUS'] as String? ?? '';
    if (status == 'APPROVED') {
      return _badge('Live', AppColors.primaryGreen);
    }
    if (status == 'PENDING_REVIEW') {
      return _badge('Pending Review', Colors.orange);
    }
    return null;
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  Widget _buildListingsArea() {
    if (_listingsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text(
            'No crops listed yet. Tap "Add Crop" to get started.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final listing in _listings)
          _CropListTile(
            listing: listing,
            updating: _updatingId == listing.id,
            onStatusTap: () => _openStatusPicker(listing),
          ),
      ],
    );
  }
}

class _CropListTile extends StatelessWidget {
  final Listing listing;
  final bool updating;
  final VoidCallback onStatusTap;

  const _CropListTile({
    required this.listing,
    required this.updating,
    required this.onStatusTap,
  });

  (String, Color) get _statusInfo => switch (listing.status) {
        'AVAILABLE_NOW' => ('Available Now', AppColors.primaryGreen),
        'SOON_TO_HARVEST' => ('Soon to Harvest', Colors.orange),
        'NOT_AVAILABLE' => ('Not Available', Colors.grey),
        _ => ('Not Available', Colors.grey),
      };

  String get _label =>
      listing.cropIcon ?? listing.categoryName ?? 'Crop';

  String get _imageUrl => listing.image ?? '';

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _statusInfo;

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
          _buildThumbnail(),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          if (updating)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            GestureDetector(
              onTap: onStatusTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more, size: 14, color: statusColor),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (_imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Image.network(
            _imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _iconThumbnail(),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.green.shade50,
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return _iconThumbnail();
  }

  Widget _iconThumbnail() {
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.green.shade50,
      child: const Icon(Icons.eco, color: AppColors.primaryGreen, size: 22),
    );
  }
}