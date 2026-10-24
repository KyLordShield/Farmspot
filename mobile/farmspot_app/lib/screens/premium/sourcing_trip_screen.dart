import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../models/sourcing.dart';
import '../../services/sourcing_service.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import '../../widgets/premium_widgets.dart';
import '../farm_profile_screen.dart';
import '../farm_directions_screen.dart';

class SourcingTripScreen extends StatefulWidget {
  final List<String> requestedCrops;
  final SourcingGateway? gateway;
  final Future<LatLng?> Function()? locate;
  const SourcingTripScreen({
    super.key,
    this.requestedCrops = const [],
    this.gateway,
    this.locate,
  });
  @override
  State<SourcingTripScreen> createState() => _SourcingTripScreenState();
}

class _SourcingTripScreenState extends State<SourcingTripScreen> {
  SourcingMatches? _results;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final position =
          await (widget.locate?.call() ?? LocationService.tryBuyerPosition());
      if (!mounted) return;
      final results = await (widget.gateway ?? SourcingService.instance)
          .fetchMatches(position: position);
      if (mounted)
        setState(() {
          _results = results;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  final Set<String> _expandedFarms = {};

  Widget _cropGroup(
    String label,
    List<String> crops,
    Color color,
    bool expanded,
  ) {
    if (crops.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 30,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  crops.join(', '),
                  maxLines: expanded ? null : 2,
                  overflow: expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(SourcingFarm farm) {
    final expanded = _expandedFarms.contains(farm.id);
    final manyCrops =
        farm.crops.length > 4 || farm.crops.join(', ').length > 65;
    final hasLocation = farm.latitude != null && farm.longitude != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PremiumCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        farm.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkGreen,
                        ),
                      ),
                      if (farm.barangay.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            farm.barangay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        farm.distanceKm == null
                            ? 'Distance'
                            : '${farm.distanceKm!.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkGreen,
                        ),
                      ),
                      if (farm.distanceKm == null)
                        Text(
                          'unavailable',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.infoSage,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${farm.crops.length} of ${_results!.requestedCrops.length} requested crops matched',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.infoSage,
              ),
            ),
            _cropGroup(
              'Available now',
              farm.availableCrops,
              AppColors.primaryGreen,
              expanded,
            ),
            _cropGroup(
              'Soon to harvest',
              farm.upcomingCrops,
              AppColors.warningAmber,
              expanded,
            ),
            if (manyCrops)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() {
                    if (expanded) {
                      _expandedFarms.remove(farm.id);
                    } else {
                      _expandedFarms.add(farm.id);
                    }
                  }),
                  child: Text(expanded ? 'Show fewer crops' : 'Show all crops'),
                ),
              ),
            if (farm.needsConfirmation)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 15,
                      color: AppColors.warningAmber,
                    ),
                    const SizedBox(width: 5),
                    const Expanded(
                      child: Text(
                        'Older listings: confirm availability.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warningAmber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FarmProfileScreen(farmId: farm.id),
                    ),
                  ),
                  icon: const Icon(Icons.agriculture_outlined, size: 16),
                  label: const Text('View farm'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: !hasLocation
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FarmDirectionsScreen(
                              farmId: farm.id,
                              farmName: farm.name,
                              farmPosition: LatLng(
                                farm.latitude!,
                                farm.longitude!,
                              ),
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.directions_outlined, size: 16),
                  label: const Text('Directions'),
                ),
              ],
            ),
            if (!hasLocation)
              const Text(
                'Farm location unavailable.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          const PremiumScreenHeader(
            title: 'Matching farms',
            subtitle: 'Available now and upcoming crops from your list',
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          '${_results!.farms.length} ${_results!.farms.length == 1 ? 'farm found' : 'farms found'}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.infoSage,
                          ),
                        ),
                        if (!_results!.hasBuyerLocation &&
                            _results!.farms.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Location unavailable. Showing farms by name.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (_results!.farms.isEmpty)
                          const PremiumEmptyState(
                            icon: Icons.agriculture_outlined,
                            title: 'No matching farms yet',
                            message:
                                'No available or upcoming listings match your saved crops. Try again later or update your list.',
                          ),
                        for (final farm in _results!.farms) _card(farm),
                        if (_results!.missingCrops.isNotEmpty)
                          PremiumCard(
                            background: AppColors.warningSoft,
                            child: Text(
                              'No available or upcoming listings for: ${_results!.missingCrops.join(', ')}',
                            ),
                          ),
                        const SizedBox(height: 12),
                        const Text(
                          'Confirm availability, harvest timing, quantity, price, and pickup with the farm. Pull down to refresh current listings.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
