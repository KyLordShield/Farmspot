import 'package:flutter/material.dart';
import '../theme.dart';

/// Simple placeholder data model for a crop listing.
/// Swap `imageUrl` for a real network/asset image once backend is ready.
class CropListing {
  final String cropName;
  final String farmName;
  final String cropType;
  final String distance;
  final String status;
  final String barangay;
  final String sitio;
  final String postedLabel;
  final String expiresLabel;
  final String contactNumber;
  final IconData placeholderIcon;

  const CropListing({
    required this.cropName,
    required this.farmName,
    this.cropType = 'Vegetable',
    this.distance = '0.4 km away',
    this.status = 'P_status',
    this.barangay = 'Brgy. Sudlon',
    this.sitio = 'Sitio Maraag',
    this.postedLabel = 'today',
    this.expiresLabel = '3 days',
    this.contactNumber = '0900-000-0000',
    this.placeholderIcon = Icons.eco,
  });
}

/// Rounded green square used as a temporary image placeholder.
/// Replace with Image.network(imageUrl) / Image.asset(...) later.
class CropImagePlaceholder extends StatelessWidget {
  final double size;
  final IconData icon;
  final double borderRadius;

  const CropImagePlaceholder({
    super.key,
    required this.size,
    this.icon = Icons.eco,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.fieldBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.fieldBorder),
      ),
      child: Icon(icon, color: AppColors.primaryGreen, size: size * 0.5),
    );
  }
}

/// Search bar + camera icon shown inside the green home header.
class HomeSearchField extends StatelessWidget {
  final VoidCallback? onCameraTap;
  const HomeSearchField({super.key, this.onCameraTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.black45),
          const SizedBox(width: 8),
          const Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search Crops or farms',
                hintStyle: TextStyle(color: Colors.black45, fontSize: 14),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          GestureDetector(
            onTap: onCameraTap,
            child: const Icon(Icons.camera_alt_outlined, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

/// Pill-shaped filter chip ("All", "Leafy Vegetables", ...).
class CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGreen : AppColors.fieldBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : AppColors.fieldBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Row card representing a crop listing on the Home screen.
class CropCard extends StatelessWidget {
  final CropListing listing;
  final VoidCallback onTap;

  const CropCard({super.key, required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.fieldBorder.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CropImagePlaceholder(size: 56, icon: listing.placeholderIcon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Crop name:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    listing.farmName,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    listing.distance,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.fieldBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                listing.status,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom navigation bar: Home, Map, Insights, Profile.
class FarmSpotBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FarmSpotBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home, 'Home'),
      (Icons.map_outlined, 'Map'),
      (Icons.insights, 'Insights'),
      (Icons.person_outline, 'Profile'),
    ];

    return BottomAppBar(
      color: Colors.white,
      elevation: 8,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (i) {
            final selected = i == currentIndex;
            final color = selected ? AppColors.primaryGreen : Colors.black45;
            return GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(items[i].$1, color: color, size: 24),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$2,
                    style: TextStyle(color: color, fontSize: 11),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
