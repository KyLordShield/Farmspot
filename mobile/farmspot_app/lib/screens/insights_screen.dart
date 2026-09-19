import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import '../widgets/seller_widgets.dart';
import '../models/insights.dart';
import '../services/auth_service.dart';
import '../services/insights_service.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'seller/my_farm_screen.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _isSeller = false;

  late Future<InsightsPayload> _payloadFuture;
  InsightsPayload? _payload;

  @override
  void initState() {
    super.initState();
    _loadSellerStatus();
    _payloadFuture = InsightsService.fetchInsights();
  }

  /// Pull-to-refresh: fetch fresh insights while keeping current data on screen.
  Future<void> _refresh() async {
    final next = InsightsService.fetchInsights();
    setState(() => _payloadFuture = next);
    try {
      final payload = await next;
      if (!mounted) return;
      setState(() => _payload = payload);
    } catch (_) {
      // Keep last good data if a pull fails; the retry button still works.
    }
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

  void _handleNavTap(int i) {
    if (i == 2) return;
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
      case 3:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => _isSeller ? const MyFarmScreen() : const ProfileScreen()),
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
                child: FutureBuilder<InsightsPayload>(
                  future: _payloadFuture,
                  builder: (context, snapshot) {
                    final payload = snapshot.data ?? _payload;
                    if (payload != null) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          ..._buildSections(payload),
                        ],
                      );
                    }
                    if (snapshot.connectionState != ConnectionState.done) {
                      return _fillScrollable(
                        const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      );
                    }
                    return _fillScrollable(
                      _ErrorRetry(
                        message: snapshot.error.toString(),
                        onRetry: () => setState(() {
                          _payloadFuture = InsightsService.fetchInsights();
                        }),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isSeller
          ? SellerBottomNav(currentIndex: 2, onTap: _handleNavTap)
          : FarmSpotBottomNav(currentIndex: 2, onTap: _handleNavTap),
    );
  }

  /// Wraps a centered child in a full-height scrollable so the RefreshIndicator
  /// can receive the pull gesture even while loading or showing an error.
  Widget _fillScrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          width: constraints.maxWidth,
          child: child,
        ),
      ),
    );
  }

  List<Widget> _buildSections(InsightsPayload payload) {
    final sections = <Widget>[];

    for (final section in payload.sections) {
      sections.add(
        _InsightListCard(
          icon: section.type == 'top_searched'
              ? Icons.search
              : Icons.category,
          title: section.title,
          entries: section.entries,
        ),
      );
      sections.add(const SizedBox(height: 16));
    }

    sections.add(
      _SeasonalTrendCard(trends: payload.seasonalTrends),
    );

    return sections;
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      color: AppColors.primaryGreen,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Crop Insights',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Demand & Seasonal Trends',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _InsightListCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<RankEntry> entries;

  const _InsightListCard({
    required this.icon,
    required this.title,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: icon,
      title: title,
      child: entries.isEmpty
          ? const Text(
              'No data yet.',
              style: TextStyle(color: Colors.black45),
            )
          : Column(
              children: List.generate(entries.length, (i) {
                final entry = entries[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '#${entry.rank}',
                          style: const TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(entry.label),
                      ),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
    );
  }
}

class _SeasonalTrendCard extends StatelessWidget {
  final List<SeasonalTrend> trends;

  const _SeasonalTrendCard({required this.trends});

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.show_chart,
      title: 'SEASONAL TRENDS',
      child: trends.isEmpty
          ? const Text(
              'No seasonal data yet.',
              style: TextStyle(color: Colors.black45),
            )
          : Column(
              children: [
                Row(
                  children: const [
                    Expanded(
                      child: Text(
                        'MONTH',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'TRENDING CROPS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),
                ...trends.map(
                  (trend) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            trend.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(trend.crops.join(', ')),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _Card({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
