import 'package:flutter/material.dart';

import '../models/farm_profile.dart';
import '../services/farm_service.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import 'product_detail_screen.dart';

/// Buyer-facing Farm Profile: farm banner + quick stats, then a sticky tab bar
/// (All / Available Now / Soon to Harvest / Not Available) filtering the farm's
/// full listing set client-side against the single fetch done on load.
class FarmProfileScreen extends StatefulWidget {
  final String farmId;

  /// Preloaded profile (used by tests so the screen renders without network).
  /// When provided, the screen skips the fetch and — since no real visit
  /// happened — skips the visit log too.
  final FarmProfileData? initialData;

  const FarmProfileScreen({
    super.key,
    required this.farmId,
    this.initialData,
  });

  @override
  State<FarmProfileScreen> createState() => _FarmProfileScreenState();
}

class _FarmProfileScreenState extends State<FarmProfileScreen> {
  static const _tabs = <({String label, String? status})>[
    (label: 'All', status: null),
    (label: 'Available Now', status: 'AVAILABLE_NOW'),
    (label: 'Soon to Harvest', status: 'SOON_TO_HARVEST'),
    (label: 'Not Available', status: 'NOT_AVAILABLE'),
  ];

  FarmProfileData? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _profile = widget.initialData;
      _loading = false;
      return;
    }
    _load();
    // Fire-and-forget visit log: never blocks the UI, errors ignored silently.
    FarmService.logFarmVisit(widget.farmId);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await FarmService.fetchFarmProfile(widget.farmId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              TextButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;
    return DefaultTabController(
      length: _tabs.length,
      child: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildHeader(profile),
                _buildStats(profile),
              ],
            ),
          ),
        ],
        body: Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                children: [
                  for (final tab in _tabs) _buildTabContent(profile, tab.status),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(FarmProfileData profile) {
    final photo = profile.firstPhoto;
    final hasPhoto = photo == null || photo.trim().isEmpty;
    return Container(
      width: double.infinity,
      height: 240,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: AppColors.fieldBackground),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPhoto)
            Icon(Icons.agriculture, size: 96, color: AppColors.primaryGreen)
          else
            Image.network(
              photo,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.agriculture,
                size: 96,
                color: AppColors.primaryGreen,
              ),
            ),
          // Subtle dark gradient over the bottom third so the white-on-photo
          // title/location stay legible over any cover image.
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
                if (profile.barangay != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          profile.barangay!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(FarmProfileData profile) {
    final distance = profile.distanceLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      // Expanded per stat so the two pairs always share the row width
      // proportionally; a long distance label can never push past the row's
      // bounds (e.g. 18px overflow on a 360px phone), truncating instead.
      child: Row(
        children: [
          Expanded(
            child: _StatPair(
              icon: Icons.eco,
              value: '${profile.availableNowCount}',
              label: 'Available Now',
            ),
          ),
          if (distance != null) ...[
            const SizedBox(width: 24),
            Expanded(
              child: _StatPair(
                icon: Icons.near_me_outlined,
                value: distance,
                label: 'from you',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x22000000)),
        ),
      ),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppColors.primaryGreen,
        unselectedLabelColor: Colors.black54,
        indicatorColor: AppColors.primaryGreen,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: [
          for (final tab in _tabs) Tab(text: tab.label),
        ],
      ),
    );
  }

  Widget _buildTabContent(FarmProfileData profile, String? status) {
    final listings = profile.filtered(status);
    if (listings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No listings in this category right now',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: CropCardGrid(
        listings: listings,
        onTap: (listing) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(listing: listing),
          ),
        ),
      ),
    );
  }
}

/// Compact icon + value/label stat shown under the farm banner.
class _StatPair extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatPair({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primaryGreen, size: 20),
        ),
        const SizedBox(width: 8),
        // Expanded bounds the text to whatever the icon leaves over — without a
        // tight bound the Texts size to their intrinsic width and push the
        // whole pair past its Expanded slot (the overflow reported on device).
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }
}