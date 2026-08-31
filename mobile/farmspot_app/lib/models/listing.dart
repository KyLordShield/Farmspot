import '../widgets/home_widgets.dart';

/// Raw listing data as returned by GET /api/listings and /api/listings/{id}.
class Listing {
  final String id;
  final String? cropIcon;
  final String status;
  final String? harvestDate;
  final String? expiryDate;
  final String? image;
  final String? createdAt;
  final String? categoryName;
  final String? farmName;
  final String? barangay;
  final String? farmerName;
  final String? farmerMobileNumber;

  Listing({
    required this.id,
    this.cropIcon,
    required this.status,
    this.harvestDate,
    this.expiryDate,
    this.image,
    this.createdAt,
    this.categoryName,
    this.farmName,
    this.barangay,
    this.farmerName,
    this.farmerMobileNumber,
  });

  factory Listing.fromJson(Map<String, dynamic> json) {
    return Listing(
      id: json['id'] as String,
      cropIcon: json['crop_icon'] as String?,
      status: json['status'] as String? ?? 'NOT_AVAILABLE',
      harvestDate: json['harvest_date'] as String?,
      expiryDate: json['expiry_date'] as String?,
      image: json['image'] as String?,
      createdAt: json['created_at'] as String?,
      categoryName: (json['category'] as Map?)?['name'] as String?,
      farmName: (json['farm'] as Map?)?['name'] as String?,
      barangay: (json['farm'] as Map?)?['barangay'] as String?,
      farmerName: (json['farmer'] as Map?)?['name'] as String?,
      farmerMobileNumber: (json['farmer'] as Map?)?['mobile_number'] as String?,
    );
  }

  /// Converts to the existing UI-facing CropListing shape, so existing
  /// widgets (CropCard, ProductDetailScreen) don't need to change.
  /// NOTE: `distance` and `sitio` have no backend source yet (no geolocation
  /// implemented, and the pilot is single-sitio) — kept as sensible defaults.
  /// `placeholderIcon` also stays default for now — real photos (LST_IMAGE)
  /// aren't wired to Image.network yet, that's a separate future task.
  CropListing toCropListing() {
    return CropListing(
      cropName: categoryName ?? 'Crop',
      farmName: farmName ?? 'Unknown Farm',
      cropType: categoryName ?? 'Vegetable',
      status: status,
      barangay: barangay ?? 'Brgy. Sudlon',
      postedLabel: _relativeDate(createdAt),
      expiresLabel: _relativeExpiry(expiryDate),
      contactNumber: farmerMobileNumber ?? 'N/A',
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