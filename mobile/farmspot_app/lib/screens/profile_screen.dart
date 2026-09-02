import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/home_widgets.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'insights_screen.dart';
import 'edit_profile_screen.dart';
import 'seller/farm_setup_details_screen.dart';
import 'seller/seller_home_screen.dart';
import '../services/auth_service.dart';
import '../services/farm_service.dart';
import '../models/farm_setup_data.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _firstName = '';
  String _lastName = '';
  String _address = 'Address';
  String _phone = '';
  bool _isSeller = false;
  bool _hasFarm = false;
  bool _sellerBusy = false;
  String? _sellerError;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async => _syncStateFromServer();

  static bool _parseSellerFlag(Map<String, dynamic> user) {
    final v = user['USR_IS_SELLER'];
    if (v is int) return v == 1;
    return int.tryParse(v?.toString() ?? '') == 1;
  }

  /// Fetches latest user + farm count from the server and updates local state.
  Future<void> _syncStateFromServer() async {
    var user = await AuthService.fetchUser();
    user ??= await AuthService.getUser();
    if (user == null || !mounted) return;

    final fullName = (user['USR_NAME'] as String? ?? '').trim();
    final parts = fullName.split(' ');
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final phone = user['USR_MOBILE_NUMBER'] as String? ?? '';
    final isSeller = _parseSellerFlag(user);

    final farms = await FarmService.getFarms();
    if (!mounted) return;

    setState(() {
      _firstName = firstName;
      _lastName = lastName;
      _phone = phone;
      _isSeller = isSeller;
      _hasFarm = farms.isNotEmpty;
    });
  }

  /// Calls the real activate/deactivate endpoint, re-fetches fresh state,
  /// then either navigates to the seller shell (activation) or stays on
  /// profile (deactivation). On failure, reverts the switch and shows an
  /// inline error.
  Future<void> _toggleSeller(bool enable) async {
    if (_sellerBusy) return;

    setState(() {
      _sellerBusy = true;
      _sellerError = null;
    });

    final error = enable
        ? await AuthService.activateSeller()
        : await AuthService.deactivateSeller();

    if (error != null) {
      if (!mounted) return;
      setState(() {
        _sellerBusy = false;
        _sellerError = error;
      });
      return;
    }

    await _syncStateFromServer();
    if (!mounted) return;
    setState(() => _sellerBusy = false);

    if (enable && _isSeller) {
      if (_hasFarm) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SellerHomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FarmSetupDetailsScreen(
              farmSetupData: FarmSetupData(),
            ),
          ),
        );
      }
    }
  }

  void _handleNavTap(int i) {
    if (i == 3) return; // already on Profile
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
      case 2:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const InsightsScreen()),
        );
        break;
    }
  }

  Future<void> _openEditProfile() async {
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          firstName: _firstName,
          lastName: _lastName,
          address: _address,
          phone: _phone,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _firstName = result['firstName'] ?? _firstName;
        _lastName = result['lastName'] ?? _lastName;
        _address = result['address'] ?? _address;
        _phone = result['phone'] ?? _phone;
      });
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // close the dialog first
              await AuthService.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false, // clears the whole nav stack
              );
            },
            child: const Text('Log out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = '$_firstName $_lastName';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeaderCard(fullName),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsRow(),
                  const SizedBox(height: 16),
                  _buildBecomeSellerCard(),
                  const SizedBox(height: 20),
                  const Text(
                    'ACCOUNT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _accountTile(
                    icon: Icons.person_outline,
                    label: 'Personal Info',
                    value: fullName,
                    onTap: _openEditProfile,
                  ),
                  _accountTile(
                    icon: Icons.phone_outlined,
                    label: 'Contact Number',
                    value: _phone,
                    onTap: _openEditProfile,
                  ),
                  _accountTile(
                    icon: Icons.logout,
                    label: 'log out',
                    value: '',
                    iconColor: Colors.red,
                    labelColor: Colors.red,
                    onTap: _logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FarmSpotBottomNav(
        currentIndex: 3,
        onTap: _handleNavTap,
      ),
    );
  }

  Widget _buildHeaderCard(String fullName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.primaryGreen,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: OutlinedButton.icon(
              onPressed: _openEditProfile,
              icon: const Icon(Icons.edit, size: 14, color: Colors.white),
              label: const Text(
                'Edit Profile',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                child: Text(
                  _firstName.isNotEmpty ? _firstName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 12, color: Colors.white70),
                        const SizedBox(width: 2),
                        Text(
                          _address,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Buyer Account',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: const [
        Expanded(child: _StatBox(label: 'Searches', value: '0')),
        SizedBox(width: 10),
        Expanded(child: _StatBox(label: 'Farm Visited', value: '0')),
        SizedBox(width: 10),
        Expanded(child: _StatBox(label: 'Contact Made', value: '0')),
      ],
    );
  }

  Widget _buildBecomeSellerCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6EC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.storefront, color: AppColors.primaryGreen, size: 30),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Become a Seller\nList your crops and appear on the farm map',
                  style: TextStyle(fontSize: 12, height: 1.3),
                ),
              ),
              Switch(
                value: _isSeller,
                activeColor: AppColors.primaryGreen,
                onChanged: _sellerBusy ? null : _toggleSeller,
              ),
            ],
          ),
        ),
        if (_sellerError != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sellerError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _accountTile({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    Color iconColor = AppColors.primaryGreen,
    Color labelColor = Colors.black87,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: labelColor, fontWeight: FontWeight.w500),
              ),
            ),
            if (value.isNotEmpty)
              Text(value, style: const TextStyle(color: Colors.black45, fontSize: 12)),
            if (label != 'log out') ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }
}
