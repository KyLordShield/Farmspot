class SavedFarm {
  final String id, name, barangay;
  final String? photoUrl;
  final double? latitude, longitude;
  final bool available;
  final List<String> availableCrops, upcomingCrops;
  const SavedFarm({
    required this.id,
    required this.name,
    this.barangay = '',
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.available = true,
    this.availableCrops = const [],
    this.upcomingCrops = const [],
  });
  bool get hasLocation => latitude != null && longitude != null;
  factory SavedFarm.fromJson(Map<String, dynamic> json) => SavedFarm(
    id: json['id'] as String,
    name: json['name'] as String,
    barangay: json['barangay'] as String? ?? '',
    photoUrl: json['photo_url'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    available: json['available'] == true,
    availableCrops: (json['available_crops'] as List? ?? []).cast<String>(),
    upcomingCrops: (json['upcoming_crops'] as List? ?? []).cast<String>(),
  );
}
