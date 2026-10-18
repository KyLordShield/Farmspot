/// A seller entry in the buyer-facing seller directory: one row from
/// GET /api/sellers or GET /api/search.
///
/// A "seller" is the farmer record (FMR_ID) rather than the user account, which
/// is the identity the rest of the app already reports against when a buyer
/// flags the person behind a listing instead of the crop. [name] is the linked
/// account's USR_NAME and can be blank for an unlinked farmer, so the UI must
/// guard it rather than assume a value.
class SellerSummary {
  final String id;

  /// USR_ID of the account behind the farmer. The profile screen opens on this
  /// (every profile has an account), so a tap works even though the directory
  /// is grouped by the farmer record.
  final String userId;

  final String name;

  /// Real profile photo of the seller, or null when they have none set.
  final String? photoUrl;

  /// How many of the seller's approved, pin-active farms carry a public
  /// listing. Never counts an empty farm.
  final int farmCount;

  /// AVAILABLE_NOW listings across those farms — the same meaning the farm card
  /// and the seller profile give the figure.
  final int activeListingsCount;

  const SellerSummary({
    required this.id,
    required this.name,
    this.userId = '',
    this.photoUrl,
    this.farmCount = 0,
    this.activeListingsCount = 0,
  });

  factory SellerSummary.fromJson(Map<String, dynamic> json) {
    return SellerSummary(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      photoUrl: json['photo_url'] as String?,
      farmCount: (json['farm_count'] as num?)?.toInt() ?? 0,
      activeListingsCount:
          (json['active_listings_count'] as num?)?.toInt() ?? 0,
    );
  }
}
