class BuyRequest {
  final String id, crop, frequency, note, pickupLocation, buyerId, buyerName;
  final String buyerPhone;
  final bool buyerIsPremium;
  final DateTime? buyerPremiumExpiresAt;
  final double? latitude, longitude;
  bool get hasPin => latitude != null && longitude != null;
  final double quantityKg;
  final double? distanceKm;
  final int responseCount;
  final DateTime? updatedAt;
  const BuyRequest({
    required this.id,
    required this.crop,
    required this.quantityKg,
    required this.frequency,
    this.note = '',
    this.pickupLocation = '',
    this.buyerId = '',
    this.buyerName = '',
    this.buyerPhone = '',
    this.buyerIsPremium = false,
    this.buyerPremiumExpiresAt,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.responseCount = 0,
    this.updatedAt,
  });
  String get quantityLabel =>
      '${quantityKg.toStringAsFixed(quantityKg == quantityKg.roundToDouble() ? 0 : 2)} kg';
  String get frequencyLabel => frequency == 'weekly' ? 'Weekly' : 'One-time';
  factory BuyRequest.fromJson(Map<String, dynamic> json) {
    final buyer = json['buyer'] as Map?;
    final location = json['location'] as Map?;
    return BuyRequest(
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      id: json['id'] as String,
      crop: json['crop'] as String,
      quantityKg: (json['quantity_kg'] as num).toDouble(),
      frequency: json['frequency'] as String,
      note: json['note'] as String? ?? '',
      pickupLocation: json['pickup_location'] as String? ?? '',
      buyerId: buyer?['id'] as String? ?? '',
      buyerName: buyer?['name'] as String? ?? 'Buyer',
      buyerPhone: buyer?['phone'] as String? ?? '',
      buyerIsPremium: buyer?['is_premium'] == true,
      buyerPremiumExpiresAt: DateTime.tryParse(
        buyer?['premium_expires_at'] as String? ?? '',
      ),
      latitude: (location?['latitude'] as num?)?.toDouble(),
      longitude: (location?['longitude'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      responseCount: (json['response_count'] as num?)?.toInt() ?? 0,
    );
  }
}
