import 'package:flutter/material.dart';
import '../theme.dart';

/// Compact labels used only inside request cards.
class RequestPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool highlighted;
  const RequestPill(
    this.label, {
    super.key,
    this.icon,
    this.highlighted = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: highlighted ? AppColors.successSoft : const Color(0xFFF2F5F0),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: AppColors.mutedGreen),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
              color: highlighted ? AppColors.darkGreen : AppColors.mutedGreen,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Long notes remain readable without making every card tall by default.
class RequestNote extends StatefulWidget {
  final String text;
  const RequestNote(this.text, {super.key});
  @override
  State<RequestNote> createState() => _RequestNoteState();
}

class _RequestNoteState extends State<RequestNote> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.text,
        maxLines: _expanded || widget.text.length <= 90 ? null : 2,
        overflow: _expanded || widget.text.length <= 90
            ? TextOverflow.visible
            : TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          height: 1.35,
          color: Colors.black54,
        ),
      ),
      if (widget.text.length > 90)
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(
              _expanded ? 'Show less' : 'Read more',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryGreen,
              ),
            ),
          ),
        ),
    ],
  );
}
