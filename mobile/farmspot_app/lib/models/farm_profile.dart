import '../widgets/home_widgets.dart';
import 'listing.dart';
import 'listing_review.dart';

/// One farm photo as the backend sends it: `{id, url, is_primary}`.
///
/// The backend orders the gallery so the cover (is_primary) comes first, which
/// is what lets the profile banner treat the first entry as the banner. Keep
/// the ordering when a screen shows the strip so the green ring on the cover
/// always matches the big photo above it.
class FarmPhotoEntry {
  final String id;
  final String url;
  final bool isPrimary;

  const FarmPhotoEntry({
    required this.id,
    required this.url,
    this.isPrimary = false,
  });

  factory FarmPhotoEntry.fromJson(Map<String, dynamic> json) {
    return FarmPhotoEntry(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      isPrimary: json['is_primary'] == true,
    );
  }
}

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
  final List<FarmPhotoEntry> photos;
  final List<CropListing> listings;

  /// Whole-farm rating, aggregated by the backend over the VISIBLE reviews of
  /// every listing on this farm (`rating_average` / `rating_count` in the
  /// payload). Absent when nothing is rated yet, so an unreviewed farm shows
  /// nothing rather than "0.0".
  final RatingSummary ratingSummary;

  /// The person who runs this farm, as returned by the backend's `owner` block.
  ///
  /// Null when the farm's farmer row is unlinked to an account. Both ids are
  /// kept because they are different accusations: reporting the *seller* (their
  /// repeated behaviour as a farmer) is not the same as reporting their
  /// *account*, and the moderator queue stores them under separate target types.
  final String? ownerFarmerId;
  final String? ownerUserId;
  final String? ownerName;

  FarmProfileData({
    required this.id,
    required this.name,
    this.description = '',
    this.barangay,
    this.latitude,
    this.longitude,
    this.status = 'APPROVED',
    this.photos = const [],
    this.ratingSummary = const RatingSummary.none(),
    this.listings = const [],
    this.ownerFarmerId,
    this.ownerUserId,
    this.ownerName,
  });

  /// Whether "Report this farm" can be offered at all. A farm with no resolvable
  /// farmer id cannot be reported, and the entry point is hidden rather than
  /// shown and failing on submit.
  bool get canReportOwner => (ownerFarmerId ?? '').trim().isNotEmpty;

  /// The farm, or the person behind it, as a name for a report sheet subtitle.
  String get reportSubjectName => ownerName?.trim().isNotEmpty == true ? ownerName! : name;

  factory FarmProfileData.fromJson(Map<String, dynamic> json) {
    final farm = json['farm'] as Map? ?? const {};
    final owner = json['owner'] as Map?;
    final rawListings = json['listings'] as List? ?? const [];
    return FarmProfileData(
      id: farm['id'] as String? ?? '',
      name: farm['name'] as String? ?? '',
      description: farm['description'] as String? ?? '',
      barangay: farm['barangay'] as String?,
      latitude: _toDouble(farm['latitude']),
      longitude: _toDouble(farm['longitude']),
      status: farm['status'] as String? ?? 'APPROVED',
      photos: _farmPhotosFromJson(farm['photos']),
      ratingSummary: RatingSummary.fromListingJson(Map<String, dynamic>.from(farm)),
      ownerFarmerId: owner?['farmer_id'] as String?,
      ownerUserId: owner?['user_id'] as String?,
      ownerName: owner?['name'] as String?,
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

  /// Parses the payload's `photos` list into entries, ordered cover-first.
  ///
  /// The backend already sends the primary first; the stable re-sort is a
  /// defensive guarantee for a payload that ever arrives unordered, so the
  /// screens can keep trusting "index 0 is the banner".
  static List<FarmPhotoEntry> _farmPhotosFromJson(Object? raw) {
    if (raw is! List) return const [];
    final entries = raw
        .whereType<Map>()
        .map((e) => FarmPhotoEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    entries.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return 0;
    });
    return entries;
  }

  static double? _toDouble(dynamic value) =>
      value == null ? null : num.tryParse(value.toString())?.toDouble();

  /// Every photo's URL in the backend's cover-first order. The thin seam the
  /// photo viewer and the banner use — they only need URLs, not ids/flags.
  List<String> get photoUrls => [for (final photo in photos) photo.url];

  /// First farm photo (used as the profile header banner), or null when the
  /// farm has no photos uploaded yet. The gallery is cover-first by contract,
  /// so this is the cover photo when one exists.
  String? get firstPhoto => photoUrls.isNotEmpty ? photoUrls.first : null;

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