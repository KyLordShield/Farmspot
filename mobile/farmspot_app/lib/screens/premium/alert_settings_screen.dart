import 'package:flutter/material.dart';
import '../../premium/premium_mock_data.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/premium_widgets.dart';

class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({super.key});

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  bool _notificationsOn = true;
  late List<MockAlertRule> _rules;

  @override
  void initState() {
    super.initState();
    _rules = List.of(mockAlertRules);
  }

  Future<void> _addAlert() async {
    String crop = kPremiumCrops.first;
    double radius = 8;

    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Add Available Now alert',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Get notified early when this crop becomes available near you.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Crop',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in kPremiumCrops)
                        ChoiceChip(
                          label: Text(c),
                          selected: crop == c,
                          selectedColor: AppColors.successSoft,
                          onSelected: (_) => setSheet(() => crop = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Within ${radius.toStringAsFixed(0)} km',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Slider(
                    value: radius,
                    min: 1,
                    max: 20,
                    divisions: 19,
                    activeColor: AppColors.primaryGreen,
                    label: '${radius.toStringAsFixed(0)} km',
                    onChanged: (v) => setSheet(() => radius = v),
                  ),
                  const SizedBox(height: 8),
                  FarmSpotButton(
                    label: 'Save alert',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );

    if (added == true && mounted) {
      setState(() {
        _rules.add(
          MockAlertRule(
            id: 'a${_rules.length + 1}',
            crop: crop,
            radiusKm: radius,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const PremiumScreenHeader(
              title: 'Alert settings',
              subtitle: 'Early “Available Now” rules',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  PremiumCard(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Push notifications',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Turn off to pause all Business alerts.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _notificationsOn,
                      activeThumbColor: AppColors.primaryGreen,
                      onChanged: (v) => setState(() => _notificationsOn = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(title: 'YOUR ALERT RULES'),
                  const SizedBox(height: 8),
                  if (_rules.isEmpty)
                    const PremiumEmptyState(
                      icon: Icons.notifications_none,
                      title: 'No alerts yet',
                      message:
                          'Add a crop and a distance. We will ping you when it becomes Available Now.',
                    )
                  else
                    for (final rule in _rules) ...[
                      PremiumCard(
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.successSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.eco,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rule.crop,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'Within ${rule.radiusKm.toStringAsFixed(0)} km',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: rule.enabled && _notificationsOn,
                              activeThumbColor: AppColors.primaryGreen,
                              onChanged: !_notificationsOn
                                  ? null
                                  : (v) => setState(() => rule.enabled = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FarmSpotButton(
                  label: 'Add alert',
                  onPressed: _addAlert,
                  trailingIcon: Icons.add,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
