import 'package:flutter/material.dart';

import '../theme.dart';

/// Where tapping a notification row should take the user.
///
/// `none` is a real answer, not a fallback for laziness: a report update has a
/// RPT_ID behind it but the app has no report-detail screen to open, and a
/// completed setup may have no farm yet. Guessing a destination for those would
/// either dead-end the tap or invent a screen that does not exist, so the row
/// just marks itself read.
enum NotificationTarget { listing, profile, myFarm, none }

/// The presentation for one NOTIF_TYPE: the leading icon, its tint, and where a
/// tap goes.
///
/// The taxonomy is a closed list owned by the server (NOTIF_TYPE is an enum in
/// the migration), so this switch is exhaustive on purpose — adding a word
/// there is a contract change that has to be mirrored here. The `_` arm still
/// exists because a row that arrived from a newer backend must render as a
/// generic bell rather than crash the whole inbox.
({IconData icon, Color color, NotificationTarget target}) notificationStyleFor(
  String type,
) {
  switch (type) {
    // Listing lifecycle. These carry the LST_ID the row is about, which is what
    // makes them worth deep-linking: "your listing expires tomorrow" is only
    // actionable if the tap lands on that listing.
    case 'LISTING_EXPIRING_SOON':
      return (
        icon: Icons.hourglass_bottom_rounded,
        color: AppColors.warningAmber,
        target: NotificationTarget.listing,
      );
    case 'LISTING_EXPIRED':
      return (
        icon: Icons.event_busy_rounded,
        color: AppColors.errorTerracotta,
        target: NotificationTarget.listing,
      );
    // The one LISTING_* type with no destination. The listing is gone from the
    // feed AND from My Farm, so the product detail screen can only fail here —
    // a dead tap that leaves the farmer wondering whether the app broke. Tapping
    // it just marks it read, which is the receipt they actually need.
    case 'LISTING_REMOVED':
      return (
        icon: Icons.remove_circle_outline_rounded,
        color: AppColors.errorTerracotta,
        target: NotificationTarget.none,
      );

    // Account state. These are about the person, not a record, so they open the
    // profile where the account and seller-mode controls live.
    case 'SELLER_DEACTIVATED':
      return (
        icon: Icons.storefront_outlined,
        color: AppColors.warningAmber,
        target: NotificationTarget.profile,
      );
    case 'ACCOUNT_SUSPENDED':
      return (
        icon: Icons.block_rounded,
        color: AppColors.errorTerracotta,
        target: NotificationTarget.profile,
      );
    case 'ACCOUNT_REACTIVATED':
      return (
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.primaryGreen,
        target: NotificationTarget.profile,
      );

    // No report-detail screen exists in the app yet, so a report update is
    // read-only here rather than deep-linking to a destination that would have
    // to be invented.
    case 'REPORT_UPDATE':
      return (
        icon: Icons.shield_outlined,
        color: AppColors.infoSage,
        target: NotificationTarget.none,
      );

    case 'HARVEST_REMINDER':
      return (
        icon: Icons.agriculture_rounded,
        color: AppColors.primaryGreen,
        target: NotificationTarget.listing,
      );

    case 'SETUP_COMPLETE':
      return (
        icon: Icons.task_alt_rounded,
        color: AppColors.primaryGreen,
        target: NotificationTarget.myFarm,
      );

    // Whitelist gate. Both are about the person being allowed to sell, and both
    // point at the profile, which is where seller mode is switched on — the
    // backend deliberately does not flip those flags for them (see
    // WhitelistController), so the profile is exactly where the next step is.
    case 'WHITELIST_APPROVED':
      return (
        icon: Icons.verified_user_rounded,
        color: AppColors.primaryGreen,
        target: NotificationTarget.profile,
      );
    // Distinct icon from WHITELIST_APPROVED on purpose: both arrive green and
    // both are about selling, and reusing one icon would make the pair read as
    // the same event twice.
    case 'SELLER_REACTIVATED':
      return (
        icon: Icons.storefront_rounded,
        color: AppColors.infoSage,
        target: NotificationTarget.profile,
      );

    default:
      return (
        icon: Icons.notifications_none_rounded,
        color: AppColors.mutedGreen,
        target: NotificationTarget.none,
      );
  }
}
