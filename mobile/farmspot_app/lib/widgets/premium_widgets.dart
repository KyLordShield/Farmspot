import 'package:flutter/material.dart';
import '../theme.dart';
import 'buy_request_widgets.dart';

/// Small amber "PREMIUM" / "NEW" tag used next to Business tools.
class PremiumBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const PremiumBadge({super.key, this.label = 'PREMIUM', this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.premiumGoldSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.premiumGold.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.premiumGold,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Tiny lock overlay for free-user quick actions.
class LockedBadge extends StatelessWidget {
  final double size;

  const LockedBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.premiumGold,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Icon(Icons.lock, size: size * 0.55, color: Colors.white),
    );
  }
}

/// Boxy bordered card matching Home/Profile cards, with optional amber strip.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;
  final VoidCallback? onTap;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.background,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor ?? AppColors.fieldBorder.withValues(alpha: 0.7),
        ),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}

/// Section label used above tool groups ("BUSINESS TOOLS", etc.).
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
              color: Colors.black45,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Status pill for requests / verification (open, fulfilled, pending…).
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color? background;

  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.background,
  });

  factory StatusChip.open() => const StatusChip(
    label: 'Open',
    color: AppColors.primaryGreen,
    background: AppColors.successSoft,
  );

  factory StatusChip.fulfilled() => const StatusChip(
    label: 'Fulfilled',
    color: AppColors.infoSage,
    background: AppColors.infoSoft,
  );

  factory StatusChip.closed() => StatusChip(
    label: 'Closed',
    color: Colors.grey.shade700,
    background: Colors.grey.shade200,
  );

  factory StatusChip.pending() => const StatusChip(
    label: 'Pending verification',
    color: AppColors.premiumGold,
    background: AppColors.premiumGoldSoft,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Green app-bar style header with back button for premium screens.
class PremiumScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const PremiumScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 16),
      color: AppColors.primaryGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: 'Back',
              ),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...?actions,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 56, right: 8),
              child: Text(
                subtitle!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Empty-state block used across premium screens.
class PremiumEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PremiumEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primaryGreen.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(icon, size: 34, color: AppColors.primaryGreen),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Saved-farm row with distance, crops, reliability hint, and watch toggles.
class FarmTile extends StatelessWidget {
  final String name;
  final String location;
  final String distanceLabel;
  final List<String> availableCrops;
  final String reliabilityHint;
  final Set<String> watchingCrops;
  final ValueChanged<String>? onToggleWatch;
  final VoidCallback? onTap;

  const FarmTile({
    super.key,
    required this.name,
    required this.location,
    required this.distanceLabel,
    required this.availableCrops,
    required this.reliabilityHint,
    required this.watchingCrops,
    this.onToggleWatch,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.agriculture,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$location · $distanceLabel',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reliabilityHint,
            style: const TextStyle(fontSize: 12, color: AppColors.mutedGreen),
          ),
          if (availableCrops.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Available now',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black45,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final crop in availableCrops)
                  _WatchChip(
                    crop: crop,
                    watching: watchingCrops.contains(crop),
                    onToggle: onToggleWatch == null
                        ? null
                        : () => onToggleWatch!(crop),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WatchChip extends StatelessWidget {
  final String crop;
  final bool watching;
  final VoidCallback? onToggle;

  const _WatchChip({required this.crop, required this.watching, this.onToggle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: watching
              ? AppColors.premiumGoldSoft
              : AppColors.fieldBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: watching ? AppColors.premiumGold : AppColors.fieldBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              watching ? Icons.visibility : Icons.visibility_outlined,
              size: 14,
              color: watching ? AppColors.premiumGold : Colors.black45,
            ),
            const SizedBox(width: 4),
            Text(
              crop,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: watching ? AppColors.premiumGold : Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              watching ? 'Watching' : 'Watch',
              style: TextStyle(
                fontSize: 10,
                color: watching ? AppColors.premiumGold : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact buyer-owned request card.
class RequestCard extends StatelessWidget {
  final String crop, quantityLabel, frequencyLabel, pickupLabel, note;
  final VoidCallback onRemove;
  final int responseCount;
  final VoidCallback? onViewResponses, onViewPin;
  final bool hasPin, busy;
  const RequestCard({
    super.key,
    required this.crop,
    required this.quantityLabel,
    required this.frequencyLabel,
    required this.pickupLabel,
    this.note = '',
    required this.onRemove,
    required this.responseCount,
    this.onViewResponses,
    this.hasPin = false,
    this.onViewPin,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) => PremiumCard(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                crop,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkGreen,
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove request',
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.errorTerracotta,
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 5,
          children: [
            RequestPill(quantityLabel, highlighted: true),
            RequestPill(frequencyLabel),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Visible to sellers',
                style: TextStyle(fontSize: 11, color: AppColors.mutedGreen),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        RequestNote(pickupLabel),
        if (note.isNotEmpty) ...[const SizedBox(height: 5), RequestNote(note)],
        if (hasPin)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onViewPin,
              icon: const Icon(Icons.location_on_outlined, size: 15),
              label: const Text('View map pin'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                padding: const EdgeInsets.symmetric(horizontal: 0),
                minimumSize: const Size(44, 40),
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'No location shared',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onViewResponses,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              side: const BorderSide(color: Color(0xFFCBDCCB)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chat_bubble_outline, size: 16),
            label: Text(
              responseCount > 0
                  ? 'View seller messages ($responseCount)'
                  : 'View seller messages',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Numbered stop on the weekly sourcing trip timeline.
class StopTile extends StatelessWidget {
  final int number;
  final String farmName;
  final List<String> crops;
  final String etaLabel;
  final bool isLast;
  final VoidCallback? onCall;
  final VoidCallback? onSms;

  const StopTile({
    super.key,
    required this.number,
    required this.farmName,
    required this.crops,
    required this.etaLabel,
    this.isLast = false,
    this.onCall,
    this.onSms,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppColors.primaryGreen.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: PremiumCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farmName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Buy: ${crops.join(', ')}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      etaLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedGreen,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _ActionChip(
                          icon: Icons.phone_outlined,
                          label: 'Call',
                          onTap: onCall,
                        ),
                        const SizedBox(width: 8),
                        _ActionChip(
                          icon: Icons.sms_outlined,
                          label: 'SMS',
                          onTap: onSms,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryGreen,
        side: const BorderSide(color: AppColors.primaryGreen),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Profile / settings row that may show a PREMIUM tag when locked.
class BusinessToolRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showPremiumTag;
  final VoidCallback onTap;

  const BusinessToolRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.showPremiumTag = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryGreen, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
            if (showPremiumTag) ...[
              const PremiumBadge(compact: true),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right, color: Colors.black26, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Compact Home card: title + PREMIUM tag + 4 quick-action buttons.
class BusinessToolsQuickCard extends StatelessWidget {
  final bool locked;
  final VoidCallback onBuyRequest;
  final VoidCallback onSavedFarms;
  final VoidCallback onSourcingTrip;
  final VoidCallback onAlerts;

  const BusinessToolsQuickCard({
    super.key,
    required this.locked,
    required this.onBuyRequest,
    required this.onSavedFarms,
    required this.onSourcingTrip,
    required this.onAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.campaign_outlined, 'Buy Request', onBuyRequest),
      (Icons.favorite_border, 'Saved Farms', onSavedFarms),
      (Icons.route_outlined, 'Sourcing List', onSourcingTrip),
      (Icons.notifications_active_outlined, 'Alerts', onAlerts),
    ];

    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      borderColor: locked
          ? AppColors.premiumGold.withValues(alpha: 0.45)
          : AppColors.primaryGreen.withValues(alpha: 0.25),
      background: locked
          ? AppColors.premiumGoldSoft.withValues(alpha: 0.35)
          : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Business tools',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(width: 8),
              if (locked)
                const PremiumBadge(compact: true)
              else
                const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: AppColors.primaryGreen,
                ),
              const Spacer(),
              if (locked)
                const Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: AppColors.premiumGold,
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Horizontally scrollable so four 48px+ targets fit on 360dp phones
          // without crushing labels. On wider phones the row still looks like
          // one compact strip.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  _QuickActionButton(
                    icon: actions[i].$1,
                    label: actions[i].$2,
                    locked: locked,
                    onTap: actions[i].$3,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool locked;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 78,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: AppColors.primaryGreen, size: 24),
                  if (locked)
                    const Positioned(
                      right: -6,
                      top: -4,
                      child: LockedBadge(size: 14),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Footer note used on buy-request / upgrade screens.
class OfflinePaymentNote extends StatelessWidget {
  final String text;

  const OfflinePaymentNote({
    super.key,
    this.text =
        'Price and payment with farmers are always agreed directly. FarmSpot does not handle payments.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.infoSage.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.infoSage),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.infoSage,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [screen] via Navigator.push.
Future<T?> pushPremiumScreen<T>(BuildContext context, Widget screen) {
  return Navigator.of(
    context,
  ).push<T>(MaterialPageRoute(builder: (_) => screen));
}
