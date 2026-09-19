import 'package:flutter/material.dart';

/// Best-effort Material icon for a real listing's card, derived from the crop
/// name / category label (the same keyword-heuristic style the seller crop
/// picker uses). Falls back to a generic leaf so cards always render.
IconData cropIconForCrop(String cropName, String? categoryName) {
  final crop = cropName.toLowerCase();
  final category = (categoryName ?? '').toLowerCase();

  if (category.contains('veget')) return Icons.spa;
  if (category.contains('fruit')) return Icons.local_florist;
  if (category.contains('grain') ||
      category.contains('rice') ||
      category.contains('cereal')) {
    return Icons.grain;
  }
  if (category.contains('livest') ||
      category.contains('poult') ||
      category.contains('animal')) {
    return Icons.pets;
  }
  if (category.contains('fish') || category.contains('aqua')) {
    return Icons.set_meal_outlined;
  }

  if (crop.contains('corn') ||
      crop.contains('maize') ||
      crop.contains('rice') ||
      crop.contains('wheat')) {
    return Icons.grain;
  }
  if (crop.contains('eggplant')) return Icons.circle;
  if (crop.contains('cabbage') || crop.contains('lettuce')) return Icons.spa;
  return Icons.eco;
}