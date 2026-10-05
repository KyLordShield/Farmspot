import '../widgets/home_widgets.dart';
import 'listing_review.dart';

/// A single photo in a listing's gallery, as returned by the backend's
/// `photos` array: [{id, url, is_primary}].
class ListingPhoto {
  final String id;
  final String url;
  final bool isPrimary;

  const ListingPhoto({
    required this.id,
    required this.url,
    required this.isPrimary,
  });

  factory ListingPhoto.fromJson(Map<String, dynamic> json) {
    return ListingPhoto(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }
}

/// Raw listing data as returned by GET /api/listings and /api/listings/{id}.
class Listing {
  final String id;
  final String? cropIcon;
  final String status;
  final String? availability;
  final String? harvestDate;
  final String? expiryDate;
  final String? image;
  final String? description;
  final List<ListingPhoto> photos;
  final String? createdAt;
  final String? categoryId;
  final String? categoryName;
  final String? farmName;
  final String? farmId;
  final String? barangay;
  final String? farmerName;
  final String? farmerMobileNumber;

  /// FMR_ID of the farmer behind this listing. Needed to file a report against
  /// the seller as a person, which is a different accusation from reporting
  /// the crop. Null when the seller row is unlinked.
  final String? farmerId;

  /// Star average and visible review count, as sent by the backend's
  /// `rating_average` / `rating_count` pair.
  ///
  /// Defaults to [RatingSummary.none] rather than to 0.0/0: an endpoint that
  /// did not ask for the summary must leave a card with no stars at all, and
  /// the only way to get that is for "not loaded" and "loaded and empty" to be
  /// the same value.
  final RatingSummary ratings;

  Listing({
    required this.id,
    this.cropIcon,
    required this.status,
    this.availability,
    this.harvestDate,
    this.expiryDate,
    this.image,
    this.description,
    this.photos = const [],
    this.createdAt,
    this.categoryId,
    this.categoryName,
    this.farmName,
    this.farmId,
    this.barangay,
    this.farmerName,
    this.farmerMobileNumber,
    this.farmerId,
    this.ratings = const RatingSummary.none(),
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
    final photosRaw = json['photos'] as List? ?? const [];
    return Listing(
      id: json['id'] as String,
      cropIcon: json['crop_icon'] as String?,
      status: json['status'] as String? ?? 'NOT_AVAILABLE',
      availability: json['availability'] as String?,
      harvestDate: json['harvest_date'] as String?,
      expiryDate: json['expiry_date'] as String?,
      image: json['image'] as String?,
      description: json['description'] as String?,
      photos: photosRaw
          .map((p) => ListingPhoto.fromJson(p as Map<String, dynamic>))
          .toList(),
      createdAt: json['created_at'] as String?,
      categoryId: (json['category'] as Map?)?['id'] as String?,
      categoryName: (json['category'] as Map?)?['name'] as String?,
      farmName: (json['farm'] as Map?)?['name'] as String?,
      farmId: (json['farm'] as Map?)?['id'] as String?,
      barangay: (json['farm'] as Map?)?['barangay'] as String?,
      farmerName: (json['farmer'] as Map?)?['name'] as String?,
      farmerMobileNumber: (json['farmer'] as Map?)?['mobile_number'] as String?,
      farmerId: (json['farmer'] as Map?)?['id'] as String?,
      ratings: RatingSummary.fromListingJson(json),
    );
  }

  /// Converts to the existing UI-facing CropListing shape, so existing
  /// widgets (CropCard, ProductDetailScreen) don't need to change.
  /// NOTE: `distance` and `sitio` have no backend source yet (no geolocation
  /// implemented, and the pilot is single-sitio) — kept as sensible defaults.
  CropListing toCropListing() {
    return CropListing(
      // crop_icon holds the seller-typed crop name (e.g. "Screen-Test Crop");
      // fall back to the category label for older entries with no name.
      cropName: (cropIcon?.trim().isNotEmpty ?? false)
          ? cropIcon!
          : (categoryName ?? 'Crop'),
      farmName: farmName ?? 'Unknown Farm',
      // Backend listing identity so detail-screen contact actions can log
      // against the real listing, and the farm id so cards can tap into the
      // Farm Profile screen.
      listingId: id,
      farmId: farmId,
      // Category filtering keys off the real category, not the crop name.
      cropType: categoryName ?? 'Vegetable',
      categoryId: categoryId,
      // Carried through so the product detail screen can report the seller
      // as a person, not just the crop.
      farmerId: farmerId,
      status: status,
      imageUrl: image,
      description: description,
      photoUrls: photos.map((p) => p.url).toList(growable: false),
      barangay: barangay ?? 'Brgy. Sudlon',
      postedLabel: _relativeDate(createdAt),
      expiresLabel: _relativeExpiry(expiryDate),
      contactNumber: farmerMobileNumber ?? 'N/A',
      // Carried into the UI-facing shape so cards can show stars without
      // re-reading the raw Listing, and so the detail screen's rate sheet has a
      // starting point.
      ratings: ratings,
    );
  }

  static String _relativeDate(String? dateStr) {
    if (dateStr == null) return 'recently';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return 'recently';
    final diff = DateTime.now().difference(date).inDays;
    if (diff <= 0) return 'today';
    if (diff == 1) return '1 day ago';
    return '$diff days ago';
  }

  static String _relativeExpiry(String? dateStr) {
    if (dateStr == null) return 'unknown';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return 'unknown';
    final diff = date.difference(DateTime.now()).inDays;
    if (diff < 0) return 'expired';
    if (diff == 0) return 'today';
    if (diff == 1) return '1 day';
    return '$diff days';
  }
}
