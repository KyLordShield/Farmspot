import 'package:flutter/material.dart';
import 'premium_checkout_screen.dart';
import '../../premium/premium_state.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/premium_widgets.dart';

class PremiumUpgradeScreen extends StatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  State<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends State<PremiumUpgradeScreen> {
  bool _purchasing = false;

  static const _features = [
    (
      Icons.bolt_outlined,
      'Crop and saved farm alerts',
      'Choose crops and get notified when any farm has them available.',
    ),
    (
      Icons.campaign_outlined,
      'Buy Requests',
      'Tell nearby farms what you need in one shout.',
    ),
    (
      Icons.route_outlined,
      'Weekly Sourcing List',
      'Find all matching farms, nearest first.',
    ),
    (Icons.favorite_border, 'Saved Farms', 'Keep trusted farms one tap away.'),
    (
      Icons.workspace_premium_outlined,
      'Premium member badge',
      'Show your active Premium membership on your profile and buy requests.',
    ),
  ];

  Future<void> _startPremium(BuildContext context) async {
    if (_purchasing || isPremium.value) return;
    setState(() => _purchasing = true);
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PremiumCheckoutScreen()),
      );
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: isPremium,
    builder: (context, active, _) =>
        active ? _activeSubscription(context) : _upgradeOffer(context),
  );

  Widget _activeSubscription(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          const PremiumScreenHeader(
            title: 'Your subscription',
            subtitle: 'FarmSpot Business',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 16),
                const Icon(
                  Icons.check_circle,
                  size: 64,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Premium is active',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGreen,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your Business tools are unlocked on Home and Profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 24),
                PremiumCard(
                  background: AppColors.successSoft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FARMSPOT BUSINESS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkGreen,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Access until $premiumExpiryLabel',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Monthly membership · no automatic renewal',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.mutedGreen,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FarmSpotButton(
                  label: 'Back to Profile',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Buy requests, Saved Farms, and Weekly Sourcing are available. Crop and saved farm alerts are available in Notifications. Your Premium member badge appears automatically while your plan is active.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _upgradeOffer(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const PremiumScreenHeader(
              title: 'FarmSpot Business',
              subtitle: 'For restaurants, carinderias, caterers & resellers',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  PremiumCard(
                    background: AppColors.premiumGoldSoft,
                    borderColor: AppColors.premiumGold.withValues(alpha: 0.4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const PremiumBadge(label: 'NEW · BUSINESS'),
                        const SizedBox(height: 10),
                        const Text(
                          'Source produce faster from Maraag farms',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGreen,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Built for busy kitchens that buy every week — not for one-off shoppers.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black.withValues(alpha: 0.7),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader(title: 'WHAT YOU GET'),
                  const SizedBox(height: 8),
                  for (final f in _features) ...[
                    _FeatureRow(icon: f.$1, title: f.$2, body: f.$3),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  const SectionHeader(title: 'FREE VS PREMIUM'),
                  const SizedBox(height: 8),
                  const _ComparisonTable(),
                  const SizedBox(height: 20),
                  PremiumCard(
                    child: Column(
                      children: [
                        const Text(
                          'Monthly Premium plan',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGreen,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'One month of Premium access. Renew when you need it.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ValueListenableBuilder<bool>(
                          valueListenable: isPremium,
                          builder: (context, active, _) => Column(
                            children: [
                              if (active) ...[
                                Text(
                                  'Active until $premiumExpiryLabel',
                                  style: const TextStyle(
                                    color: AppColors.primaryGreen,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              IgnorePointer(
                                ignoring: _purchasing,
                                child: FarmSpotButton(
                                  label: active
                                      ? 'Back to Profile'
                                      : (_purchasing
                                            ? 'Opening...'
                                            : 'Continue to checkout'),
                                  onPressed: active
                                      ? () => Navigator.of(context).pop()
                                      : () => _startPremium(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your membership includes Buy Requests, Saved Farms, Weekly Sourcing, crop alerts and a Premium member badge.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
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

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.premiumGoldSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.premiumGold, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable();

  static const _rows = [
    ('Browse, search & map', true, true),
    ('Contact sellers', true, true),
    ('Basic insights', true, true),
    ('Saved Farms', false, true),
    ('Buy Requests', false, true),
    ('Crop and saved farm alerts', false, true),
    ('Weekly Sourcing List', false, true),
    ('Premium member badge', false, true),
  ];

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.fieldBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Feature',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Free',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Premium',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.premiumGold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < _rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppColors.fieldBorder.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      _rows[i].$1,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(child: _check(_rows[i].$2, free: true)),
                  Expanded(child: _check(_rows[i].$3, free: false)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _check(bool yes, {required bool free}) {
    return Icon(
      yes ? Icons.check_circle : Icons.remove_circle_outline,
      size: 18,
      color: yes
          ? (free ? AppColors.primaryGreen : AppColors.premiumGold)
          : Colors.black26,
    );
  }
}
