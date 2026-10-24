import 'package:flutter/material.dart';
import '../../premium/premium_mock_data.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/premium_widgets.dart';

class BackupAlertsScreen extends StatelessWidget {
  const BackupAlertsScreen({super.key});

  void _toast(BuildContext context, String action, String farm) {
    showFarmAlert(
      context,
      type: FarmAlertType.info,
      title: action,
      message: 'Preview only — $action for $farm would open here.',
      buttonLabel: 'Okay',
    );
  }

  @override
  Widget build(BuildContext context) {
    final alerts = mockBackupAlerts;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const PremiumScreenHeader(
              title: 'Backup Supplier Alerts',
              subtitle: 'Problem → nearby farms that still have it',
            ),
            Expanded(
              child: alerts.isEmpty
                  ? const PremiumEmptyState(
                      icon: Icons.swap_horiz,
                      title: 'No backup alerts yet',
                      message:
                          'When a saved farm runs out of a crop you are watching, alternatives appear here.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: alerts.length,
                      itemBuilder: (context, index) {
                        final alert = alerts[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == alerts.length - 1 ? 0 : 16,
                          ),
                          child: _AlertBlock(
                            alert: alert,
                            onCall: (f) => _toast(context, 'Call', f),
                            onMessage: (f) => _toast(context, 'Message', f),
                            onDirections: (f) =>
                                _toast(context, 'Directions', f),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertBlock extends StatelessWidget {
  final MockBackupAlert alert;
  final ValueChanged<String> onCall;
  final ValueChanged<String> onMessage;
  final ValueChanged<String> onDirections;

  const _AlertBlock({
    required this.alert,
    required this.onCall,
    required this.onMessage,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // PROBLEM
        PremiumCard(
          background: AppColors.errorSoft,
          borderColor: AppColors.errorTerracotta.withValues(alpha: 0.35),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.errorTerracotta,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.outOfStockFarm} is out of ${alert.crop}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.errorTerracotta,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.whenLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.errorTerracotta.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Nearby farms that still have it',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.mutedGreen,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // SOLUTION ranked list
        for (var i = 0; i < alert.backups.length; i++) ...[
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? AppColors.primaryGreen
                            : AppColors.fieldBackground,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i == 0
                              ? AppColors.primaryGreen
                              : AppColors.fieldBorder,
                        ),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: i == 0 ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        alert.backups[i].name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      '${alert.backups[i].distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniAction(
                      icon: Icons.phone_outlined,
                      label: 'Call',
                      onTap: () => onCall(alert.backups[i].name),
                    ),
                    const SizedBox(width: 6),
                    _MiniAction(
                      icon: Icons.chat_bubble_outline,
                      label: 'Message',
                      onTap: () => onMessage(alert.backups[i].name),
                    ),
                    const SizedBox(width: 6),
                    _MiniAction(
                      icon: Icons.directions_outlined,
                      label: 'Directions',
                      onTap: () => onDirections(alert.backups[i].name),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (i < alert.backups.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryGreen,
          side: BorderSide(
            color: AppColors.primaryGreen.withValues(alpha: 0.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          minimumSize: const Size(0, 40),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
