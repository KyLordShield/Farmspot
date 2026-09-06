/// Performance totals for a farm from the farm-owner's perspective
/// (GET /api/farms/{id}/stats): how many times the farm's profile was opened,
/// how many buyers contacted listings on it, and how many of its listings are
/// currently Available Now + ACTIVE.
class FarmStats {
  final int profileViews;
  final int buyerContacts;
  final int activeListings;

  const FarmStats({
    required this.profileViews,
    required this.buyerContacts,
    required this.activeListings,
  });

  factory FarmStats.fromJson(Map<String, dynamic> json) {
    return FarmStats(
      profileViews: (json['profile_views'] as num?)?.toInt() ?? 0,
      buyerContacts: (json['buyer_contacts'] as num?)?.toInt() ?? 0,
      activeListings: (json['active_listings'] as num?)?.toInt() ?? 0,
    );
  }
}