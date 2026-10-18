import 'farm_pin.dart';
import 'listing_review.dart';

/// A person's public profile, as returned by GET /api/users/{userId}/profile.
///
/// This is the account behind a farm, a chat counterparty, or a seller row in
/// the search previews. [farms] is empty for a pure buyer — the screen then
/// shows the contact card alone. There is deliberately no listing list here:
/// the farm profile owns the crop wall, this screen is just the person.
class UserProfile {
  final String id;
  final String name;
  final String? address;
  final String? phone;

  /// Cloudinary URL of the account's profile photo, or null when none is set.
  final String? photo;

  /// Whether this account runs any farm (has a farmer record). Decides the
  /// role badge and the report target.
  final bool isSeller;

  /// FMR_ID behind a seller, used to report the person as a seller; null for a
  /// pure buyer, who is reported by account.
  final String? farmerId;

  final int farmCount;
  final int activeListingsCount;
  final List<FarmPin> farms;

  /// Whole-seller rating over the visible reviews on their listings. Has no
  /// ratings for a pure buyer, so the screen renders nothing rather than 0.0.
  final RatingSummary rating;

  const UserProfile({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.photo,
    this.isSeller = false,
    this.farmerId,
    this.farmCount = 0,
    this.activeListingsCount = 0,
    this.farms = const [],
    this.rating = const RatingSummary.none(),
  });

  bool get hasFarms => farms.isNotEmpty;

  /// Whether this profile can be reported. A seller is reported as the farmer
  /// (their whole selling history), anyone else by account.
  bool get canReport => id.trim().isNotEmpty;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map? ?? const {};

    return UserProfile(
      id: user['id'] as String? ?? '',
      name: (user['name'] as String?)?.trim() ?? '',
      address: user['address'] as String?,
      phone: user['phone'] as String?,
      photo: user['photo'] as String?,
      isSeller: user['is_seller'] == true,
      farmerId: user['farmer_id'] as String?,
      farmCount: (json['farm_count'] as num?)?.toInt() ?? 0,
      activeListingsCount:
          (json['active_listings_count'] as num?)?.toInt() ?? 0,
      farms: (json['farms'] as List?)
              ?.whereType<Map>()
              .map((farm) => FarmPin.fromJson(Map<String, dynamic>.from(farm)))
              .where((farm) => farm.name.isNotEmpty)
              .toList() ??
          const [],
      rating: RatingSummary(
        average: json['rating_average'] == null
            ? null
            : (json['rating_average'] as num).toDouble(),
        count: (json['rating_count'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
