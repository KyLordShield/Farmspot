import 'package:flutter/material.dart';
import '../../premium/premium_mock_data.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/premium_widgets.dart';
import 'sourcing_trip_screen.dart';

class SourcingListScreen extends StatefulWidget {
  const SourcingListScreen({super.key});

  @override
  State<SourcingListScreen> createState() => _SourcingListScreenState();
}

class _SourcingListScreenState extends State<SourcingListScreen> {
  final Set<String> _crops = {
    'Pechay',
    'Tomato',
    'Cabbage',
    'Lettuce',
    'Eggplant',
  };

  void _toggleCrop(String crop) {
    setState(() {
      if (_crops.contains(crop)) {
        _crops.remove(crop);
      } else {
        _crops.add(crop);
      }
    });
  }

  void _findTrip() {
    if (_crops.isEmpty) {
      showFarmAlert(
        context,
        type: FarmAlertType.warning,
        title: 'Add crops first',
        message: 'Pick at least one crop for your weekly list.',
      );
      return;
    }
    pushPremiumScreen(
      context,
      SourcingTripScreen(requestedCrops: _crops.toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const PremiumScreenHeader(
              title: 'Weekly Sourcing List',
              subtitle: 'Find farms growing the crops you need',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  PremiumCard(
                    background: AppColors.infoSoft,
                    borderColor: AppColors.infoSage.withValues(alpha: 0.25),
                    child: const Text(
                      'Add the crops you need this week. See all matching farms, sorted from nearest to farthest.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.infoSage,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(title: 'YOUR LIST'),
                  const SizedBox(height: 8),
                  if (_crops.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No crops yet. Tap a crop below to add it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in _crops.toList()..sort())
                          InputChip(
                            label: Text(c),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _toggleCrop(c),
                            backgroundColor: AppColors.successSoft,
                            side: BorderSide(
                              color: AppColors.primaryGreen.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  const SectionHeader(title: 'ADD CROPS'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in kPremiumCrops)
                        FilterChip(
                          label: Text(c),
                          selected: _crops.contains(c),
                          selectedColor: AppColors.successSoft,
                          checkmarkColor: AppColors.primaryGreen,
                          onSelected: (_) => _toggleCrop(c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const PremiumCard(
                    background: AppColors.infoSoft,
                    child: Row(
                      children: [
                        Icon(Icons.near_me_outlined, color: AppColors.infoSage),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Nearest farms first. All matching farms are included, with no distance limit.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.infoSage,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FarmSpotButton(
                label: 'Find matching farms',
                onPressed: _findTrip,
                trailingIcon: Icons.search,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
