class PremiumAlertSettings {
  final bool enabled, savedFarms, buyRequests, cropAlerts;
  final bool pushEnabled, quietEnabled;
  final String pushFrequency, quietStart, quietEnd, dailyTime;
  final List<String> crops, availableCrops;
  final Map<String, List<String>> aliases;
  const PremiumAlertSettings({
    this.pushEnabled = false,
    this.quietEnabled = true,
    this.pushFrequency = 'hourly',
    this.quietStart = '22:00',
    this.quietEnd = '07:00',
    this.dailyTime = '09:00',
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
        pushEnabled: json['push_enabled'] == true,
        quietEnabled: json['quiet_enabled'] as bool? ?? true,
        pushFrequency: json['push_frequency'] as String? ?? 'hourly',
        quietStart: json['quiet_start'] as String? ?? '22:00',
        quietEnd: json['quiet_end'] as String? ?? '07:00',
        dailyTime: json['daily_time'] as String? ?? '09:00',
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
    'push_enabled': pushEnabled,
    'push_frequency': pushFrequency,
    'quiet_enabled': quietEnabled,
    'quiet_start': quietStart,
    'quiet_end': quietEnd,
    'daily_time': dailyTime,
    'enabled': enabled,
    'saved_farms': savedFarms,
    'buy_requests': buyRequests,
    'crop_alerts': cropAlerts,
    'crops': crops,
  };
  PremiumAlertSettings copyWith({
    bool? pushEnabled,
    bool? quietEnabled,
    String? pushFrequency,
    String? quietStart,
    String? quietEnd,
    String? dailyTime,
    bool? enabled,
    bool? savedFarms,
    bool? buyRequests,
    bool? cropAlerts,
    List<String>? crops,
  }) => PremiumAlertSettings(
    pushEnabled: pushEnabled ?? this.pushEnabled,
    quietEnabled: quietEnabled ?? this.quietEnabled,
    pushFrequency: pushFrequency ?? this.pushFrequency,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
    dailyTime: dailyTime ?? this.dailyTime,
    enabled: enabled ?? this.enabled,
    savedFarms: savedFarms ?? this.savedFarms,
    buyRequests: buyRequests ?? this.buyRequests,
    cropAlerts: cropAlerts ?? this.cropAlerts,
    crops: crops ?? this.crops,
    availableCrops: availableCrops,
    aliases: aliases,
  );
}
