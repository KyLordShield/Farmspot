import '../../widgets/lottie_loader.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../models/saved_farm.dart';
import '../../premium/premium_nav.dart';
import '../../premium/premium_state.dart';
import '../../services/location_service.dart';
import '../../services/saved_farms_state.dart';
import '../../theme.dart';
import '../../widgets/premium_widgets.dart';
import '../farm_profile_screen.dart';
import '../farm_directions_screen.dart';

class SavedFarmsScreen extends StatefulWidget {
  final SavedFarmsState? savedFarms;
  const SavedFarmsScreen({super.key, this.savedFarms});
  @override
  State<SavedFarmsScreen> createState() => _SavedFarmsScreenState();
}

class _SavedFarmsScreenState extends State<SavedFarmsScreen> {
  SavedFarmsState get _saved => widget.savedFarms ?? SavedFarmsState.instance;
  bool _loading = true;
  String? _error;
  LatLng? _position;
  @override
  void initState() {
    super.initState();
    _load();
    if (isPremium.value) _locate();
    isPremium.addListener(_premiumChanged);
  }

  @override
  void dispose() {
    isPremium.removeListener(_premiumChanged);
    super.dispose();
  }

  void _premiumChanged() {
    if (isPremium.value) Future.microtask(_load);
  }

  Future<void> _locate() async {
    final position = await LocationService.tryBuyerPosition();
    if (mounted) setState(() => _position = position);
  }

  Future<void> _load() async {
    if (!isPremium.value) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      await _saved.load(refresh: true);
      if (mounted)
        setState(() {
          _loading = false;
          _error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  Future<void> _remove(SavedFarm farm) async {
    if (_saved.isBusy(farm.id)) return;
    try {
      await withFarmLottieLoading(
        context,
        () => _saved.toggle(farm.id),
        message: 'Removing saved farm...',
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    }
  }

  void _profile(SavedFarm f) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FarmProfileScreen(farmId: f.id, savedFarms: _saved),
    ),
  );
  void _directions(SavedFarm f) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FarmDirectionsScreen(
        farmId: f.id,
        farmPosition: LatLng(f.latitude!, f.longitude!),
        farmName: f.name,
      ),
    ),
  );

  Widget _card(SavedFarm f) => PremiumCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: f.photoUrl?.isNotEmpty == true
                    ? Image.network(
                        f.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.agriculture,
                          color: AppColors.primaryGreen,
                        ),
                      )
                    : const ColoredBox(
                        color: AppColors.successSoft,
                        child: Icon(
                          Icons.agriculture,
                          color: AppColors.primaryGreen,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  if (f.barangay.isNotEmpty)
                    Text(
                      f.barangay,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Unsave farm',
              onPressed: _saved.isBusy(f.id) ? null : () => _remove(f),
              icon: _saved.isBusy(f.id)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.favorite, color: AppColors.premiumGold),
            ),
          ],
        ),
        if (!f.available) ...[
          const SizedBox(height: 10),
          const Text(
            'This farm is not currently available. You can remove it from your saved list.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ] else ...[
          const SizedBox(height: 10),
          if (_position != null && f.hasLocation)
            Text(
              LocationService.distanceLabel(
                LocationService.distanceKm(
                  _position!,
                  LatLng(f.latitude!, f.longitude!),
                ),
              ),
              style: const TextStyle(fontSize: 12, color: AppColors.mutedGreen),
            ),
          const SizedBox(height: 6),
          const Text(
            'Available now',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.darkGreen,
            ),
          ),
          if (f.availableCrops.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'No crops currently listed as available.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final crop in f.availableCrops)
                  Chip(
                    label: Text(crop, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppColors.successSoft,
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          if (f.upcomingCrops.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                'Soon to harvest: ${f.upcomingCrops.join(', ')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedGreen,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: () => _profile(f),
                icon: const Icon(Icons.agriculture_outlined, size: 16),
                label: const Text('View farm'),
              ),
              OutlinedButton.icon(
                onPressed: f.hasLocation ? () => _directions(f) : null,
                icon: const Icon(Icons.directions_outlined, size: 16),
                label: const Text('Directions'),
              ),
            ],
          ),
          if (!f.hasLocation)
            const Text(
              'No map location available.',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          const PremiumScreenHeader(
            title: 'Saved Farms',
            subtitle: 'Your farms, saved to your account',
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([_saved, isPremium]),
              builder: (context, _) {
                if (!isPremium.value)
                  return PremiumEmptyState(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Premium is required',
                    message:
                        'Your saved farms stay on your account. Activate Premium to access them again.',
                    actionLabel: 'See Premium plan',
                    onAction: () => openUpgrade(context),
                  );
                if (_loading)
                  return const Center(
                    child: FarmLottieLoading(message: 'Loading saved farms...'),
                  );
                return RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.errorTerracotta,
                          ),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                      if (_saved.farms.isEmpty && _error == null)
                        const PremiumEmptyState(
                          icon: Icons.favorite_border,
                          title: 'No saved farms yet',
                          message:
                              'Tap the heart on a farm in the map or farm profile to save it here.',
                        ),
                      for (final farm in _saved.farms) ...[
                        _card(farm),
                        const SizedBox(height: 12),
                      ],
                      if (_saved.farms.isNotEmpty)
                        const Text(
                          'Availability comes from current listings. Confirm quantity and freshness with the seller. Pull down to refresh.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
