import 'crop_suggestion.dart';
import 'farm_pin.dart';
import 'seller_summary.dart';

/// Everything GET /api/search answers for one term in a single call: matching
/// crops (name + how many nearby listings carry it), farms and sellers.
///
/// One round trip rather than three so the search screen's debounced typeahead
/// and the results-screen previews cost a single request per term. The endpoint
/// is side-effect free, so a keystroke can never reach the analytics table.
class SearchSuggestions {
  final List<CropSuggestion> crops;
  final List<FarmPin> farms;
  final List<SellerSummary> sellers;

  const SearchSuggestions({
    this.crops = const [],
    this.farms = const [],
    this.sellers = const [],
  });

  static const SearchSuggestions empty = SearchSuggestions();

  bool get isEmpty => crops.isEmpty && farms.isEmpty && sellers.isEmpty;
  bool get isNotEmpty => !isEmpty;

  factory SearchSuggestions.fromJson(Map<String, dynamic> json) {
    final crops = (json['crops'] as List?)
            ?.whereType<Map>()
            .map(
              (crop) => CropSuggestion(
                name: (crop['name'] as String?)?.trim() ?? '',
                count: (crop['count'] as num?)?.toInt() ?? 0,
              ),
            )
            .where((crop) => crop.name.isNotEmpty)
            .toList() ??
        const [];

    final farms = (json['farms'] as List?)
            ?.whereType<Map>()
            .map((farm) => FarmPin.fromJson(Map<String, dynamic>.from(farm)))
            .where((farm) => farm.name.isNotEmpty)
            .toList() ??
        const [];

    final sellers = (json['sellers'] as List?)
            ?.whereType<Map>()
            .map(
              (seller) =>
                  SellerSummary.fromJson(Map<String, dynamic>.from(seller)),
            )
            .where((seller) => seller.name.isNotEmpty)
            .toList() ??
        const [];

    return SearchSuggestions(crops: crops, farms: farms, sellers: sellers);
  }
}
