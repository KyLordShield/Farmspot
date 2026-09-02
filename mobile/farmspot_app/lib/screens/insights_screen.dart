import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import '../widgets/seller_widgets.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'seller/seller_home_screen.dart';
import 'seller/my_farm_screen.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _isSeller = false;

  static const _topSearched = ['Crop Name', 'Crop Name', 'Crop Name', 'Crop Name'];

  static const _seasonalTrends = [
    ('March', 'Sili, cabbage'),
    ('June', 'Sili, cabbage'),
    ('December', 'Sili, cabbage'),
  ];

  @override
  void initState() {
    super.initState();
    _loadSellerStatus();
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
          MaterialPageRoute(builder: (_) => _isSeller ? const SellerHomeScreen() : const HomeScreen()),
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
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionCard(
                    icon: Icons.search,
                    title: 'TOP SEARCHED THIS WEEK',
                    child: Column(
                      children: List.generate(_topSearched.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '#${i + 1}',
                                  style: const TextStyle(
                                    color: AppColors.primaryGreen,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(_topSearched[i]),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.show_chart,
                    title: 'SEASONAL TRENDS',
                    child: Column(
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
                        ..._seasonalTrends.map(
                          (row) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row.$1,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Expanded(flex: 2, child: Text(row.$2)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SectionCard({
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
