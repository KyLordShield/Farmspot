/// Raw crop category as returned by GET /api/crop-categories.
class CropCategory {
  final String id;
  final String name;
  final String? icon;
  final String? description;
  final List<String> cropNames;

  CropCategory({
    required this.id,
    required this.name,
    this.icon,
    this.description,
    this.cropNames = const [],
  });

  static String _normalize(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  bool matchesCrop(String crop) {
    final key = _normalize(crop);
    return key.isNotEmpty &&
        cropNames.any((name) => (' $key ').contains(' ${_normalize(name)} '));
  }

  static int suggestIndex(List<CropCategory> categories, String crop) {
    final matches = <int>[
      for (var i = 0; i < categories.length; i++)
        if (categories[i].matchesCrop(crop)) i,
    ];
    return matches.length == 1 ? matches.single : -1;
  }

  factory CropCategory.fromJson(Map<String, dynamic> json) {
    return CropCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      cropNames:
          (json['crop_names'] as List?)?.whereType<String>().toList() ??
          const [],
    );
  }
}
