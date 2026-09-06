import 'package:flutter/material.dart';
import '../models/listing.dart';
import '../theme.dart';

/// Shared tab definitions so SellerBottomNav and FarmSpotBottomNav stay in sync.
const kSellerTabs = [
  (Icons.home, 'Home'),
  (Icons.map_outlined, 'Map'),
  (Icons.insights, 'Insights'),
  (Icons.agriculture_outlined, 'My Farm'),
  (Icons.person_outline, 'Profile'),
];

const kBuyerTabs = [
  (Icons.home, 'Home'),
  (Icons.map_outlined, 'Map'),
  (Icons.insights, 'Insights'),
  (Icons.person_outline, 'Profile'),
];

/// Green header used across the "Set Up Your Farm" wizard screens.
///
/// [onBack] adds a top-left back arrow that matches the app's existing back
/// convention on colored headers (a bare white arrow). Screen owners decide
/// what it does — a plain pop, or a "Discard changes?" guard for dirty forms.
class SetupHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  const SetupHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      color: AppColors.primaryGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              alignment: Alignment.centerLeft,
            ),
            const SizedBox(height: 6),
          ],
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// "Step X of 3 . <label>" text + progress bar shown under the header.
class StepProgress extends StatelessWidget {
  final int step;
  final int totalSteps;
  final String label;
  final double percent; // 0.0 - 1.0

  const StepProgress({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.label,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step $step of $totalSteps . $label',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(AppColors.primaryGreen),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small caption-style field label ("FARM NAME", "DESCRIPTION", ...).
class FieldLabel extends StatelessWidget {
  final String text;
  final String? badge;
  final Color badgeColor;

  const FieldLabel(this.text, {super.key, this.badge, this.badgeColor = Colors.redAccent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Colors.black54,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Text(
              badge!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: badgeColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dashed-border upload box used for ID / farm certificate uploads.
class UploadBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;

  const UploadBox({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: Colors.grey.shade400),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.fieldBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                side: const BorderSide(color: AppColors.primaryGreen),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(10),
    );
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

/// Small grey square used for photo placeholders, with an optional
/// "+" add-photo tile as the last item in a row.
class PhotoPlaceholder extends StatelessWidget {
  final bool isAddButton;
  final VoidCallback? onTap;

  const PhotoPlaceholder({super.key, this.isAddButton = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: isAddButton ? AppColors.primaryGreen : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isAddButton ? Icons.add : Icons.image_outlined,
          color: isAddButton ? Colors.white : Colors.grey.shade500,
        ),
      ),
    );
  }
}

/// Selectable square used in the "Select Crop" grid.
class CropPickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const CropPickerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF6EC) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? AppColors.primaryGreen : Colors.black45),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? AppColors.primaryGreen : Colors.black54,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row option used for "Available Now / Soon to Harvest / Not Available"
/// and for the "Which Farm?" picker.
class SelectableOptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const SelectableOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.iconColor = AppColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF6EC) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.primaryGreen : iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.primaryGreen, size: 20)
            else
              Icon(Icons.circle_outlined, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Full-width green "Next: ..." button used throughout the wizard.
class WizardNextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  const WizardNextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Icon(icon, size: 16),
          ],
        ),
      ),
    );
  }
}

/// One listing row in My Farm's management list: a large photo thumbnail, the
/// crop name on up to two lines, the tappable status chip beneath the name,
/// and the overflow (Edit/Delete) menu on the right.
///
/// The name and status live in their own column so a long crop name wraps to
/// two lines instead of being squeezed to a truncated fragment, and the status
/// control gets its own line instead of competing with the name for space.
class CropListTile extends StatelessWidget {
  final Listing listing;
  final bool updating;
  final VoidCallback onStatusTap;
  final VoidCallback onEditTap;
  final VoidCallback onDeleteTap;

  const CropListTile({
    super.key,
    required this.listing,
    required this.updating,
    required this.onStatusTap,
    required this.onEditTap,
    required this.onDeleteTap,
  });

  (String, Color) get _statusInfo => switch (listing.status) {
        'AVAILABLE_NOW' => ('Available Now', AppColors.primaryGreen),
        'SOON_TO_HARVEST' => ('Soon to Harvest', Colors.orange),
        'NOT_AVAILABLE' => ('Not Available', Colors.grey),
        _ => ('Not Available', Colors.grey),
      };

  String get _label => listing.cropIcon ?? listing.categoryName ?? 'Crop';

  String get _imageUrl => listing.image ?? '';

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = _statusInfo;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildThumbnail(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                if (updating)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  GestureDetector(
                    onTap: onStatusTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Flexible + ellipsis: the chip must shrink to its
                          // column (narrow screens / large text scale) instead
                          // of overflowing the tile like the old one-row layout.
                          Flexible(
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.expand_more, size: 14, color: statusColor),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Overflow menu stays in its own trailing slot, away from the name
          // and status, so it never competes with either.
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, size: 20, color: Colors.black45),
            onSelected: (value) {
              if (value == 'edit') {
                onEditTap();
              } else if (value == 'delete') {
                onDeleteTap();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    if (_imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 68,
          height: 68,
          child: Image.network(
            _imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _iconThumbnail(),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.green.shade50,
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return _iconThumbnail();
  }

  Widget _iconThumbnail() {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.eco, color: AppColors.primaryGreen, size: 30),
    );
  }
}

/// Farm summary card shown at the top of My Farm: farm icon, name/barangay,
/// and the "Edit Farm" action + status badge.
///
/// The name/barangay texts live in an [Expanded] column with single-line
/// ellipsis, and the actions sit on their own second row beneath the text. This
/// keeps a long real farm name from pushing into (or overlapping) the buttons
/// and prevents RenderFlex overflow at narrow 360px widths.
class FarmCard extends StatelessWidget {
  final String name;
  final String barangay;
  final String status;
  final VoidCallback onEditTap;

  const FarmCard({
    super.key,
    required this.name,
    required this.barangay,
    required this.status,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primaryGreen,
                child: Icon(Icons.agriculture, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Your Farm' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      barangay.isEmpty ? 'Farm location' : barangay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Actions on their own row so they never collide with the text.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: onEditTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Edit Farm',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_badge case final Widget badge) badge,
            ],
          ),
        ],
      ),
    );
  }

  /// "Live" only when the farm is APPROVED; otherwise show an appropriate
  /// label (Pending Review) or nothing at all.
  Widget? get _badge {
    if (status == 'APPROVED') {
      return _statusBadge('Live', AppColors.primaryGreen);
    }
    if (status == 'PENDING_REVIEW') {
      return _statusBadge('Pending Review', Colors.orange);
    }
    return null;
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

/// Bottom navigation bar for sellers: Home, Map, Insights, My Farm, Profile.
/// Kept separate from FarmSpotBottomNav (buyer nav) since it has an extra tab.
class SellerBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SellerBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Colors.white,
      elevation: 8,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(kSellerTabs.length, (i) {
            final selected = i == currentIndex;
            final color = selected ? AppColors.primaryGreen : Colors.black45;
            return GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(kSellerTabs[i].$1, color: color, size: 22),
                  const SizedBox(height: 2),
                  Text(
                    kSellerTabs[i].$2,
                    style: TextStyle(color: color, fontSize: 10),
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
