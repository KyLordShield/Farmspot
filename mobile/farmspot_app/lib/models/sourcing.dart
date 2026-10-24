class SourcingList {
  final List<String> crops, availableCrops;
  final Map<String, List<String>> aliases;
  SourcingList.fromJson(Map<String, dynamic> json)
    : crops = List<String>.from(json['crops']),
      availableCrops = List<String>.from(json['available_crops']),
      aliases = (json['crop_aliases'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      );
}

class SourcingFarm {
  final String id, name, barangay;
  final double? latitude, longitude, distanceKm;
  final List<String> crops, availableCrops, upcomingCrops;
  final bool needsConfirmation;
  SourcingFarm.fromJson(Map<String, dynamic> json)
    : id = json['id'],
      name = json['name'],
      barangay = json['barangay'] ?? '',
      latitude = (json['latitude'] as num?)?.toDouble(),
      longitude = (json['longitude'] as num?)?.toDouble(),
      distanceKm = (json['distance_km'] as num?)?.toDouble(),
      crops = List<String>.from(json['matched_crops']),
      availableCrops = List<String>.from(
        json['available_crops'] ?? json['matched_crops'],
      ),
      upcomingCrops = List<String>.from(json['upcoming_crops'] ?? []),
      needsConfirmation = json['needs_confirmation'] == true;
}

class SourcingMatches {
  final List<String> requestedCrops, missingCrops;
  final List<SourcingFarm> farms;
  final bool hasBuyerLocation;
  SourcingMatches.fromJson(Map<String, dynamic> json)
    : requestedCrops = List<String>.from(json['requested_crops']),
      missingCrops = List<String>.from(json['missing_crops']),
      farms = (json['farms'] as List)
          .map((f) => SourcingFarm.fromJson(f))
          .toList(),
      hasBuyerLocation = json['has_buyer_location'] == true;
}
