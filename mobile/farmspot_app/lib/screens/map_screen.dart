import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/farm_pin.dart';
import '../services/auth_service.dart';
import '../services/farm_service.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import '../widgets/seller_widgets.dart';
import '../widgets/farmspot_loader.dart';
import 'farm_directions_screen.dart';
import 'farm_profile_screen.dart';
import 'home_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'seller/my_farm_screen.dart';

/// Fallback buyer position — Cebu City when GPS is unavailable or denied.
/// Never throws: any geolocator failure (permission denied, services off,
/// missing plugin, no fix) falls back to this center so the map always renders.
Future<LatLng> _defaultPosition() async {
  try {
    await GeolocatorPlatform.instance.isLocationServiceEnabled();
    if (await GeolocatorPlatform.instance.checkPermission() ==
        LocationPermission.deniedForever) {
      return const LatLng(10.3178, 123.8742);
    }
    final pos = await GeolocatorPlatform.instance.getCurrentPosition();
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return const LatLng(10.3178, 123.8742);
  }
}

class MapScreen extends StatefulWidget {
  /// Fetch the public farm feed (injectable for tests). Defaults to the real
  /// endpoint and is failure-tolerant — an unreachable backend yields an empty
  /// map, never a crash.
  final Future<List<FarmPin>> Function() loadFarms;

  /// Resolve the buyer position (injectable for tests). Defaults to GPS with
  /// the Cebu City fallback; never throws.
  final Future<LatLng> Function() loadPosition;

  /// Injectable hook for "Directions": tests substitute this to capture the
  /// farm instead of pushing the real turn-by-turn screen (whose default
  /// loaders hit geolocator + the OSRM routers). When null the real
  /// [FarmDirectionsScreen] opens for the selected farm.
  final void Function(BuildContext context, FarmPin farm)?
  onDirectionsRequested;

  const MapScreen({
    super.key,
    this.loadFarms = FarmService.fetchPublicFarms,
    this.loadPosition = _defaultPosition,
    this.onDirectionsRequested,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool _isSeller = false;

  // 0 = Listing view toggle, 1 = Map view toggle.
  int _viewToggle = 1;

  final List<FarmPin> _farms = [];
  FarmPin? _selectedFarm;
  final Distance _distance = const Distance();
  LatLng _position = const LatLng(10.3178, 123.8742);
  final double _initialZoom = 14;
  bool _loadingFarms = true;
  bool _loadingPosition = true;

  @override
  void initState() {
    super.initState();
    _loadSellerStatus();
    _loadFarms();
    _loadPosition();
  }

  Future<void> _loadSellerStatus() async {
    final user = await AuthService.getUser();
    if (!mounted) return;
    if (user != null) {
      final raw = user['USR_IS_SELLER'];
      final intFlag = raw is int ? raw : int.tryParse(raw.toString()) ?? 0;
      setState(() => _isSeller = intFlag == 1);
    }
  }

  Future<void> _loadFarms() async {
    try {
      final farms = await widget.loadFarms();
      if (!mounted) return;
      setState(() {
        _farms
          ..clear()
          ..addAll(farms);
        _loadingFarms = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFarms = false);
    }
  }

  Future<void> _loadPosition() async {
    try {
      final pos = await widget.loadPosition();
      if (!mounted) return;
      setState(() {
        _position = pos;
        _loadingPosition = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPosition = false);
    }
  }

  void _handleNavTap(int i) {
    if (i == 1) return;
    switch (i) {
      case 0:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        break;
      case 2:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const InsightsScreen()),
        );
        break;
      case 3:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                _isSeller ? const MyFarmScreen() : const ProfileScreen(),
          ),
        );
        break;
      case 4:
        if (_isSeller) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        }
        break;
    }
  }

  void _openFarmProfile(FarmPin farm) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FarmProfileScreen(farmId: farm.id)),
    );
  }

  void _openDirections() {
    final farm = _selectedFarm;
    if (farm == null) return;
    final onDirectionsRequested = widget.onDirectionsRequested;
    if (onDirectionsRequested != null) {
      onDirectionsRequested(context, farm);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FarmDirectionsScreen(
          farmId: farm.id,
          farmName: farm.name,
          farmPosition: LatLng(farm.latitude, farm.longitude),
        ),
      ),
    );
  }

  String _distanceLabel(FarmPin farm) {
    final km = _distance.as(
      LengthUnit.Kilometer,
      _position,
      LatLng(farm.latitude, farm.longitude),
    );
    if (km < 0.1) return 'under 100 m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
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
              child: _viewToggle == 1 ? _buildMapView() : _buildListingView(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isSeller
          ? SellerBottomNav(currentIndex: 1, onTap: _handleNavTap)
          : FarmSpotBottomNav(currentIndex: 1, onTap: _handleNavTap),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: AppColors.primaryGreen,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Farm Map',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          _ToggleGroup(
            selected: _viewToggle,
            onChanged: (i) => setState(() => _viewToggle = i),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: _position,
              initialZoom: _initialZoom,
              onTap: (_, _) => setState(() => _selectedFarm = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.farmspot_app',
              ),
              MarkerLayer(
                markers: [_buildUserMarker(), ..._farms.map(_buildFarmMarker)],
              ),
            ],
          ),
        ),
        if (_loadingFarms || _loadingPosition)
          const Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Center(
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.all(Radius.circular(999)),
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    'Loading farms…',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ),
            ),
          ),
        if (_selectedFarm != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _FarmCard(
              farm: _selectedFarm!,
              distanceLabel: _distanceLabel(_selectedFarm!),
              onOpenProfile: () => _openFarmProfile(_selectedFarm!),
              onDirections: _openDirections,
            ),
          ),
      ],
    );
  }

  Marker _buildUserMarker() {
    return Marker(
      width: 30,
      height: 30,
      point: _position,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.blue, width: 2),
        ),
        child: const Icon(Icons.navigation, color: Colors.blue, size: 18),
      ),
    );
  }

  Marker _buildFarmMarker(FarmPin farm) {
    return Marker(
      width: 34,
      height: 34,
      point: LatLng(farm.latitude, farm.longitude),
      child: GestureDetector(
        onTap: () => setState(() => _selectedFarm = farm),
        child: const Icon(
          Icons.location_on,
          color: AppColors.primaryGreen,
          size: 34,
        ),
      ),
    );
  }

  Widget _buildListingView() {
    if (_loadingFarms) {
      return const FarmSpotLoader();
    }
    if (_farms.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No farms available right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _farms.length,
      itemBuilder: (context, index) {
        final farm = _farms[index];
        return _FarmListTile(
          farm: farm,
          subtitle:
              '${farm.barangay ?? 'No barangay'} • ${_distanceLabel(farm)}',
          onTap: () => _openFarmProfile(farm),
        );
      },
    );
  }
}

/// "Listing | Map" segmented toggle used in the header.
class _ToggleGroup extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _ToggleGroup({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [_segment('Listing', 0), _segment('Map', 1)],
      ),
    );
  }

  Widget _segment(String label, int index) {
    final bool isSelected = selected == index;
    return GestureDetector(
      onTap: () => onChanged(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }
}

/// Bottom info card shown over the map for the selected farm.
class _FarmCard extends StatelessWidget {
  final FarmPin farm;
  final String distanceLabel;

  /// Opens the farm's public profile — matches ProductDetailScreen's pattern
  /// of making the farm's name/location the affordance (never the Directions
  /// button, which is turn-by-turn navigation).
  final VoidCallback onOpenProfile;

  /// Turns on the real turn-by-turn flow for the selected farm (a distinct
  /// action from opening the profile tap target above).
  final VoidCallback onDirections;

  const _FarmCard({
    required this.farm,
    required this.distanceLabel,
    required this.onOpenProfile,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(onTap: onOpenProfile, child: _buildThumbnail()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onOpenProfile,
                      child: Text(
                        farm.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.black45,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            farm.barangay ?? 'No barangay',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                distanceLabel,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CountBadge(count: farm.activeListingsCount),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onDirections,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Directions',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    final placeholder = const CropImagePlaceholder(
      size: 52,
      icon: Icons.agriculture,
    );
    final url = farm.photoUrl;
    if (url == null || url.trim().isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

/// Green pill showing how many crops a farm currently has available.
class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 crop available' : '$count crops available';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          color: AppColors.primaryGreen,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One farm row in the Listing view — photo thumbnail, name, supporting line
/// (barangay + distance). The whole row opens the farm profile.
class _FarmListTile extends StatelessWidget {
  final FarmPin farm;
  final String subtitle;
  final VoidCallback onTap;

  const _FarmListTile({
    required this.farm,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            _buildThumbnail(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    farm.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CountBadge(count: farm.activeListingsCount),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    final placeholder = const CropImagePlaceholder(
      size: 44,
      icon: Icons.agriculture,
    );
    final url = farm.photoUrl;
    if (url == null || url.trim().isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}
