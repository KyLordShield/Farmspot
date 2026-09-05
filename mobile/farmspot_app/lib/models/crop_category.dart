/// Raw crop category as returned by GET /api/crop-categories.
class CropCategory {
  final String id;
  final String name;
  final String? icon;
  final String? description;

  CropCategory({
    required this.id,
    required this.name,
    this.icon,
    this.description,
  });

  factory CropCategory.fromJson(Map<String, dynamic> json) {
    return CropCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String?,
      description: json['description'] as String?,
    );
  }
}