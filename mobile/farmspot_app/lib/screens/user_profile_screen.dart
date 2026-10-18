import 'package:flutter/material.dart';

import '../models/report.dart';
import '../models/user_profile.dart';
import '../services/search_service.dart';
import '../theme.dart';
import '../widgets/lottie_loader.dart';
import '../widgets/report_sheet.dart';
import '../widgets/search_widgets.dart';
import 'farm_profile_screen.dart';

/// Buyer-facing profile of another person: the seller behind a farm, the other
/// side of a chat, or someone tapped in the search previews.
///
/// It is deliberately just the person — their photo, name, contact details, and
/// (only when they actually run farms) their farms. There is no listing wall:
/// the farm profile owns the crop list, and a pure buyer has none to show
/// anyway.
///
/// [loadProfile] is injectable for tests; the real HTTP-backed service is used
/// when omitted.
class UserProfileScreen extends StatefulWidget {
  /// USR_ID of the person being viewed.
  final String userId;

  /// Preloaded profile (tests render without network). When provided the screen
  /// skips the fetch.
  final UserProfile? initialProfile;

  final Future<UserProfile> Function(String userId) loadProfile;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialProfile,
    this.loadProfile = SearchService.fetchUserProfile,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await widget.loadProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _openFarm(String farmId) {
    if (farmId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FarmProfileScreen(farmId: farmId)),
    );
  }

  /// Report the person. A seller is reported as the farmer (their whole selling
  /// history is the thing to act on); anyone else is reported by account.
  Future<void> _report(UserProfile profile) async {
    if (!profile.canReport) return;
    final asFarmer = (profile.farmerId ?? '').trim().isNotEmpty;
    await showReportSheet(
      context,
      targetType: asFarmer ? ReportTargetType.farmer : ReportTargetType.user,
      targetId: asFarmer ? profile.farmerId! : profile.id,
      subjectName: profile.name.isEmpty ? 'this person' : profile.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBackground,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: FarmLottieLoading());
    }

    if (_error != null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_off_outlined,
                    size: 40, color: Colors.black38),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _profile!;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildHeader(profile),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (profile.isSeller) ...[
                _buildStatsCard(profile),
                const SizedBox(height: 20),
              ],
              _buildContactCard(profile),
              if (profile.hasFarms) ...[
                const SizedBox(height: 24),
                const SearchPreviewHeader(title: 'Farms'),
                const SizedBox(height: 6),
                for (final farm in profile.farms)
                  FarmSearchRow(
                    name: farm.name,
                    barangay: farm.barangay,
                    activeListingsCount: farm.activeListingsCount,
                    photoUrl: farm.photoUrl,
                    onTap: () => _openFarm(farm.id),
                  ),
              ],
              if (profile.canReport) ...[
                const SizedBox(height: 26),
                _buildReportLink(profile),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Green banner: back button, real profile photo, name and role. The photo is
  /// the account's own (USR_PHOTO_PATH), falling back to initials only when
  /// they have never set one.
  Widget _buildHeader(UserProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryGreen, AppColors.darkGreen],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.white24,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _ProfileAvatar(photo: profile.photo, name: profile.name),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                profile.name.isEmpty ? 'FarmSpot user' : profile.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                profile.isSeller ? 'Seller' : 'Buyer',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rating / farms / active listings, in a white card. Only shown for a
  /// seller; a buyer has nothing to summarise.
  Widget _buildStatsCard(UserProfile profile) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _ProfileStat(
              value: profile.rating.hasRatings
                  ? profile.rating.averageLabel
                  : '—',
              label: profile.rating.hasRatings
                  ? profile.rating.countLabel
                  : 'No ratings',
              icon: Icons.star_rounded,
            ),
          ),
          _divider(),
          Expanded(
            child: _ProfileStat(
              value: '${profile.farmCount}',
              label: profile.farmCount == 1 ? 'Farm' : 'Farms',
              icon: Icons.agriculture_outlined,
            ),
          ),
          _divider(),
          Expanded(
            child: _ProfileStat(
              value: '${profile.activeListingsCount}',
              label: 'Active listings',
              icon: Icons.eco_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(UserProfile profile) {
    final phone = profile.phone?.trim() ?? '';
    final address = profile.address?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 2),
            child: Text(
              'Contact',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          if (phone.isEmpty && address.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 12),
              child: Text(
                'This user has not shared any contact details.',
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
            )
          else ...[
            if (phone.isNotEmpty)
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Contact number',
                value: phone,
              ),
            if (address.isNotEmpty)
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Address',
                value: address,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportLink(UserProfile profile) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _report(profile),
        icon: const Icon(Icons.flag_outlined, size: 16, color: Colors.black45),
        label: Text(
          profile.isSeller ? 'Report this seller' : 'Report this user',
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.fieldBorder.withValues(alpha: 0.5)),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: AppColors.fieldBorder.withValues(alpha: 0.6),
      );
}

/// Large circular avatar. Shows the person's real profile photo when they have
/// one, and a plain initials disc when they do not (or the photo fails to
/// load), so the header never shows an empty hole.
class _ProfileAvatar extends StatelessWidget {
  final String? photo;
  final String name;

  const _ProfileAvatar({this.photo, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white54, width: 3),
      ),
      child: ClipOval(child: _child()),
    );
  }

  Widget _child() {
    final url = photo?.trim();
    if (url == null || url.isEmpty) return _initial();
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: 240,
      errorBuilder: (_, _, _) => _initial(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _initial();
      },
    );
  }

  Widget _initial() {
    return Container(
      color: AppColors.primaryGreen.withValues(alpha: 0.14),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: AppColors.primaryGreen,
          fontWeight: FontWeight.bold,
          fontSize: 30,
        ),
      ),
    );
  }

  /// First letters of up to two words ("Rejean Libando" -> "RL"), falling back
  /// to a neutral glyph for a blank name.
  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// One icon + value cell in the stats card.
class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _ProfileStat({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryGreen),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.darkGreen,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }
}

/// One labelled contact row (icon, small label, value) inside the contact card.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: AppColors.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.black45, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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
