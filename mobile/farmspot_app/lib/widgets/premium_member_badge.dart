import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Account membership, distinct from promotional Premium tags on locked tools.
class PremiumMemberBadge extends StatefulWidget {
  final bool isPremium;
  final DateTime? expiresAt;
  const PremiumMemberBadge({
    super.key,
    required this.isPremium,
    required this.expiresAt,
  });
  @override
  State<PremiumMemberBadge> createState() => _PremiumMemberBadgeState();
}

class _PremiumMemberBadgeState extends State<PremiumMemberBadge> {
  Timer? _timer;
  bool _expired = true;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant PremiumMemberBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPremium != widget.isPremium ||
        oldWidget.expiresAt != widget.expiresAt)
      _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final remaining = widget.expiresAt?.difference(DateTime.now());
    if (!widget.isPremium || remaining == null || remaining <= Duration.zero) {
      _expired = true;
      return;
    }
    _expired = false;
    if (remaining > const Duration(days: 1)) {
      _timer = Timer(const Duration(days: 1), () {
        if (mounted) setState(_schedule);
      });
    } else {
      _timer = Timer(remaining, () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _expired
      ? const SizedBox.shrink()
      : Tooltip(
          message: 'Active Premium membership',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.premiumGoldSoft,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: AppColors.premiumGold.withValues(alpha: .4),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium,
                  size: 13,
                  color: AppColors.premiumGold,
                ),
                SizedBox(width: 4),
                Text(
                  'Premium',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.premiumGold,
                  ),
                ),
              ],
            ),
          ),
        );
}
