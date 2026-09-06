import '../widgets/home_widgets.dart';
import 'listing.dart';

/// Data model for a farm's public profile as returned by
/// GET /api/farms/{id}/profile — the farm's details + photos plus ALL of its
/// listings (any status), already ordered by the backend by status priority
/// (Available Now -> Soon to Harvest -> Not Available) and newest first.
class FarmProfileData {
  final String id;
  final String name;
  final String description;
  final String? barangay;
  final double? latitude;
  final double? longitude;
  final String status;
  final List<String> photos;
  final List<CropListing> listings;

  FarmProfileData({
    required this.id,
    required this.name,
    this.description = '',
    this.barangay,
    this.latitude,
    this.longitude,
    this.status = 'APPROVED',
    this.photos = const [],
    this.listings = const [],
  });

  factory FarmProfileData.fromJson(Map<String, dynamic> json) {
    final farm = json['farm'] as Map? ?? const {};
    final rawListings = json['listings'] as List? ?? const [];
    return FarmProfileData(
      id: farm['id'] as String? ?? '',
      name: farm['name'] as String? ?? '',
      description: farm['description'] as String? ?? '',
      barangay: farm['barangay'] as String?,
      latitude: _toDouble(farm['latitude']),
      longitude: _toDouble(farm['longitude']),
      status: farm['status'] as String? ?? 'APPROVED',
      photos:
          (farm['photos'] as List? ?? const []).whereType<String>().toList(),
      // The flat listing shape is the same contract the buyer feed uses, so
      // the profile screen reuses Listing.toCropListing() to build the exact
      // CropListing objects CropCardGrid renders.
      listings: rawListings
          .whereType<Map>()
          .map((l) =>
              Listing.fromJson(Map<String, dynamic>.from(l)).toCropListing())
          .toList(),
    );
  }

  static double? _toDouble(dynamic value) =>
      value == null ? null : num.tryParse(value.toString())?.toDouble();

  /// First farm photo (used as the profile header banner), or null when the
  /// farm has no photos uploaded yet.
  String? get firstPhoto => photos.isNotEmpty ? photos.first : null;

  /// Count of listings currently marked AVAILABLE_NOW.
  int get availableNowCount =>
      listings.where((l) => l.status == 'AVAILABLE_NOW').length;

  /// Client-side filter against the already-fetched listing set. A null
  /// [status] returns everything (the "All" tab).
  List<CropListing> filtered(String? status) {
    if (status == null) return listings;
    return listings.where((l) => l.status == status).toList();
  }

  /// Distance label reused from the Home feed's "X km away" convention —
  /// taken from the first listing that carries one, so the profile stats row
  /// matches what CropCard shows for the same farm.
  String? get distanceLabel {
    for (final l in listings) {
      if (l.distance.isNotEmpty) return l.distance;
    }
    return null;
  }
}