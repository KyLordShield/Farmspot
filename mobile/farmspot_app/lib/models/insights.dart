/// Parsed views of GET /api/insights.
///
/// The analytics pipeline (Python step2/step3 scripts) writes ranked lists as
/// JSON into the `insight` table, and month groupings into `trend`. Laravel
/// rehydrates them, and these classes give Dart a typed view of that payload.
library;

/// One ranked entry from a numeric insight, e.g. {"rank":1,"crop":"tomato","count":4}.
class RankEntry {
  final int rank;
  final String label;
  final int value;

  const RankEntry({
    required this.rank,
    required this.label,
    required this.value,
  });

  factory RankEntry.fromJson(Map<String, dynamic> json) {
    return RankEntry(
      rank: json['rank'] as int? ?? 0,
      label: (json['crop'] ?? json['category'] ?? '') as String,
      value: (json['count'] ?? json['listing_count'] ?? 0) as int,
    );
  }
}

/// One section of the Insights screen, e.g. "Top Searched This Week".
class InsightSection {
  final String type;
  final String title;
  final List<RankEntry> entries;

  const InsightSection({
    required this.type,
    required this.title,
    required this.entries,
  });

  factory InsightSection.fromJson(Map<String, dynamic> json) {
    return InsightSection(
      type: json['type'] as String? ?? 'other',
      title: json['title'] as String? ?? '',
      entries: (json['data'] as List<dynamic>? ?? [])
          .map((e) => RankEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One seasonal month, e.g. {"period":"2026-09","title":"September","crops":["Carrot"]}.
class SeasonalTrend {
  final String period;
  final String title;
  final List<String> crops;

  const SeasonalTrend({
    required this.period,
    required this.title,
    required this.crops,
  });

  factory SeasonalTrend.fromJson(Map<String, dynamic> json) {
    return SeasonalTrend(
      period: json['period'] as String? ?? '',
      title: json['title'] as String? ?? '',
      crops: (json['crops'] as List<dynamic>? ?? [])
          .map((c) => c.toString())
          .toList(),
    );
  }
}

/// The whole GET /api/insights payload.
class InsightsPayload {
  final List<InsightSection> sections;
  final List<SeasonalTrend> seasonalTrends;

  const InsightsPayload({
    required this.sections,
    required this.seasonalTrends,
  });

  factory InsightsPayload.fromJson(Map<String, dynamic> json) {
    return InsightsPayload(
      sections: (json['insights'] as List<dynamic>? ?? [])
          .map((e) => InsightSection.fromJson(e as Map<String, dynamic>))
          .toList(),
      seasonalTrends: (json['seasonal_trends'] as List<dynamic>? ?? [])
          .map((e) => SeasonalTrend.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}