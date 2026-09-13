/// A farm pin shown on the buyer-facing map / farm listing, as returned by
/// the public endpoint GET /api/farms/public — approved, pin-active farms only
/// with their coordinates already parsed from the backend's decimal strings.
class FarmPin {
  final String id;
  final String name;
  final String? barangay;
  final double latitude;
  final double longitude;
  final int activeListingsCount;

  /// First farm photo (small thumbnail on the map card / list row), or null
  /// when the farm has none uploaded.
  final String? photoUrl;

  const FarmPin({
    required this.id,
    required this.name,
    this.barangay,
    this.latitude = 0,
    this.longitude = 0,
    this.activeListingsCount = 0,
    this.photoUrl,
  });

  factory FarmPin.fromJson(Map<String, dynamic> json) {
    return FarmPin(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed farm',
      barangay: json['barangay'] as String?,
      latitude: _toDouble(json['latitude']) ?? 0,
      longitude: _toDouble(json['longitude']) ?? 0,
      activeListingsCount:
          (json['active_listings_count'] as num?)?.toInt() ?? 0,
      photoUrl: json['photo_url'] as String?,
    );
  }

  static double? _toDouble(dynamic value) =>
      value == null ? null : num.tryParse(value.toString())?.toDouble();
}