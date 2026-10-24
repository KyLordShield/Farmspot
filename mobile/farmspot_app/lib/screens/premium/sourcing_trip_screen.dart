import 'package:flutter/material.dart';
import '../../premium/premium_mock_data.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/premium_widgets.dart';

class SourcingTripScreen extends StatelessWidget {
  final List<String> requestedCrops;

  const SourcingTripScreen({super.key, this.requestedCrops = const []});

  void _confirm(BuildContext context, String action, String farm) {
    showFarmAlert(
      context,
      type: FarmAlertType.info,
      title: action,
      message: 'Preview only — $action to confirm with $farm.',
      buttonLabel: 'Okay',
    );
  }

  @override
  Widget build(BuildContext context) {
    final requested = requestedCrops.map((c) => c.toLowerCase()).toSet();
    final farms =
        mockSavedFarms
            .where(
              (farm) =>
                  requested.isEmpty ||
                  farm.availableCrops.any(
                    (crop) => requested.contains(crop.toLowerCase()),
                  ),
            )
            .toList()
          ..sort((a, b) {
            final distance = a.distanceKm.compareTo(b.distanceKm);
            return distance != 0 ? distance : a.name.compareTo(b.name);
          });
    final available = farms
        .expand((f) => f.availableCrops)
        .map((c) => c.toLowerCase())
        .toSet();
    final missing = requestedCrops
        .where((c) => !available.contains(c.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            PremiumScreenHeader(
              title: 'Matching farms',
              subtitle: '${farms.length} matching farms · nearest first',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const PremiumCard(
                    background: AppColors.successSoft,
                    child: Row(
                      children: [
                        Icon(
                          Icons.near_me_outlined,
                          color: AppColors.primaryGreen,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'All matching farms, sorted by distance from you. No farm is excluded for being farther away.',
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: AppColors.darkGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (farms.isEmpty)
                    const PremiumEmptyState(
                      icon: Icons.agriculture_outlined,
                      title: 'No matching farms yet',
                      message: 'Try adding other crops to your sourcing list.',
                    ),
                  for (final farm in farms) ...[
                    PremiumCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  farm.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.near_me_outlined,
                                size: 14,
                                color: AppColors.mutedGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${farm.distanceKm.toStringAsFixed(1)} km away',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.mutedGreen,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            farm.barangay,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Crops from your list',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final crop in farm.availableCrops)
                                if (requested.isEmpty ||
                                    requested.contains(crop.toLowerCase()))
                                  Chip(
                                    label: Text(crop),
                                    backgroundColor: AppColors.successSoft,
                                    side: BorderSide.none,
                                  ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _confirm(context, 'Call', farm.name),
                                icon: const Icon(Icons.call_outlined, size: 16),
                                label: const Text('Call farm'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _confirm(context, 'Message', farm.name),
                                icon: const Icon(
                                  Icons.chat_bubble_outline,
                                  size: 16,
                                ),
                                label: const Text('Message'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const SectionHeader(title: 'NO MATCHES YET'),
                    const SizedBox(height: 8),
                    PremiumCard(
                      background: AppColors.warningSoft,
                      child: Text(
                        missing.join(', '),
                        style: const TextStyle(color: AppColors.warningAmber),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const OfflinePaymentNote(
                    text:
                        'Sample farms shown for this UI preview. Confirm quantity, price, and pickup with the farm.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
