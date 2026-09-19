import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/services/insights_service.dart';

// Plain `test()` (no testWidgets) so real HTTP is allowed against the local
// Laravel server. Verifies the full analytics chain end to end:
//   Python step2/step3 -> MySQL insight/trend tables -> GET /api/insights
//   -> InsightsPayload model -> sections + seasonal trends.
void main() {
  test('insights payload parses ranked sections and seasonal trends',
      () async {
    final payload = await InsightsService.fetchInsights();

    // The pipeline always writes these two insight sections when data exists.
    expect(payload.sections, isNotEmpty);
    expect(
      payload.sections.map((s) => s.type),
      containsAll(['top_searched', 'by_category']),
      reason: 'Laravel /api/insights should expose both analytic sections',
    );

    final topSearched = payload.sections.firstWhere(
      (s) => s.type == 'top_searched',
    );
    expect(topSearched.entries, isNotEmpty);
    expect(topSearched.entries.first.rank, 1);
    expect(
      topSearched.entries.map((e) => e.rank).toSet().length,
      topSearched.entries.length,
      reason: 'rank numbers must be unique across the list',
    );

    // Seasonal trends were seeded in the previous DB run.
    expect(payload.seasonalTrends, isNotEmpty);
  });
}