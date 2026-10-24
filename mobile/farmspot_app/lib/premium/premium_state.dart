import 'dart:async';
import 'package:flutter/foundation.dart';

/// Mirrors the authenticated account returned by the backend.
final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);
final ValueNotifier<bool> homeAlertDismissed = ValueNotifier<bool>(false);
DateTime? premiumExpiresAt;
Timer? _expiryTimer;
String? _premiumUserId;

String get premiumExpiryLabel {
  final date = premiumExpiresAt?.toLocal();
  if (date == null) return 'See plan details';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

void syncPremiumUser(Map<String, dynamic>? user) {
  _expiryTimer?.cancel();
  final owner = user?['USR_ID']?.toString();
  if (owner != _premiumUserId) homeAlertDismissed.value = false;
  _premiumUserId = owner;
  premiumExpiresAt = DateTime.tryParse(
    user?['USR_PREMIUM_EXPIRES_AT']?.toString() ?? '',
  );
  final flag = user?['USR_IS_PREMIUM'];
  final active =
      (flag == true || flag == 1 || flag == '1') &&
      premiumExpiresAt != null &&
      premiumExpiresAt!.isAfter(DateTime.now());
  isPremium.value = active;
  if (!active) {
    homeAlertDismissed.value = false;
    return;
  }
  _scheduleExpiryCheck(owner, premiumExpiresAt!);
}

void _scheduleExpiryCheck(String? owner, DateTime expiresAt) {
  final remaining = expiresAt.difference(DateTime.now());
  // Browser timers cannot safely represent a whole month's delay. Keep each
  // timer short, and check the actual date before withdrawing access.
  final delay = remaining > const Duration(days: 1)
      ? const Duration(days: 1)
      : remaining;
  _expiryTimer = Timer(delay, () {
    if (_premiumUserId != owner) return;
    if (expiresAt.isAfter(DateTime.now())) {
      _scheduleExpiryCheck(owner, expiresAt);
      return;
    }
    isPremium.value = false;
    homeAlertDismissed.value = false;
  });
}
