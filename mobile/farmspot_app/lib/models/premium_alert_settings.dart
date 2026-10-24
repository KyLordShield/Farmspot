class PremiumAlertSettings {
  final bool enabled, savedFarms, buyRequests, cropAlerts;
  final List<String> crops, availableCrops;
  final Map<String, List<String>> aliases;
  const PremiumAlertSettings({
    this.enabled = true,
    this.savedFarms = true,
    this.buyRequests = true,
    this.cropAlerts = true,
    this.crops = const [],
    this.availableCrops = const [],
    this.aliases = const {},
  });
  factory PremiumAlertSettings.fromJson(Map<String, dynamic> json) =>
      PremiumAlertSettings(
        enabled: json['enabled'] == true,
        savedFarms: json['saved_farms'] == true,
        buyRequests: json['buy_requests'] == true,
        cropAlerts: json['crop_alerts'] as bool? ?? true,
        crops: List<String>.from(json['crops'] ?? []),
        availableCrops: List<String>.from(json['available_crops'] ?? []),
        aliases: (json['crop_aliases'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        ),
      );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'saved_farms': savedFarms,
    'buy_requests': buyRequests,
    'crop_alerts': cropAlerts,
    'crops': crops,
  };
  PremiumAlertSettings copyWith({
    bool? enabled,
    bool? savedFarms,
    bool? buyRequests,
    bool? cropAlerts,
    List<String>? crops,
  }) => PremiumAlertSettings(
    enabled: enabled ?? this.enabled,
    savedFarms: savedFarms ?? this.savedFarms,
    buyRequests: buyRequests ?? this.buyRequests,
    cropAlerts: cropAlerts ?? this.cropAlerts,
    crops: crops ?? this.crops,
    availableCrops: availableCrops,
    aliases: aliases,
  );
}
