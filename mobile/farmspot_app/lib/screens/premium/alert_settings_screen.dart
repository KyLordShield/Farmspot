import 'package:flutter/material.dart';
import '../../models/premium_alert_settings.dart';
import '../../services/premium_alert_service.dart';
import '../../services/session_state.dart';
import '../../premium/premium_state.dart';
import '../../theme.dart';
import '../../widgets/premium_widgets.dart';
import '../../widgets/sourcing_crop_picker.dart';

class AlertSettingsScreen extends StatefulWidget {
  final PremiumAlertsGateway? gateway;
  const AlertSettingsScreen({super.key, this.gateway});
  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  PremiumAlertSettings? _settings;
  String? _error;
  bool _loading = true, _saving = false;
  PremiumAlertsGateway get _api =>
      widget.gateway ?? PremiumAlertService.instance;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _api.fetchSettings();
      if (mounted)
        setState(() {
          _settings = settings;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await _api.saveSettings(_settings!);
      if (!mounted) return;
      setState(() => _settings = saved);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Alert settings saved.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseCrops() async {
    final settings = _settings!;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SourcingCropPicker(
        catalog: {...settings.availableCrops, ...settings.crops}.toList()
          ..sort(),
        aliases: settings.aliases,
        selected: settings.crops.toSet(),
      ),
    );
    if (mounted && selected != null)
      setState(
        () => _settings = _settings!.copyWith(crops: selected.toList()..sort()),
      );
  }

  Widget _cropAlertsCard(bool premium) {
    final editable =
        premium && _settings!.enabled && _settings!.cropAlerts && !_saving;
    return _settingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Crop alerts',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              premium
                  ? 'Get notified when crops you need become Available Now at any public farm.'
                  : 'Requires premium. Your crop choices are kept for when you subscribe.',
            ),
            value: _settings!.cropAlerts,
            onChanged: !premium || !_settings!.enabled || _saving
                ? null
                : (v) => setState(
                    () => _settings = _settings!.copyWith(cropAlerts: v),
                  ),
          ),
          if (_settings!.crops.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Choose crops to start receiving alerts.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final crop in _settings!.crops)
                  InputChip(
                    label: Text(crop),
                    onDeleted: !editable
                        ? null
                        : () => setState(
                            () => _settings = _settings!.copyWith(
                              crops: _settings!.crops
                                  .where((c) => c != crop)
                                  .toList(),
                            ),
                          ),
                  ),
              ],
            ),
          OutlinedButton.icon(
            onPressed: editable ? _chooseCrops : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Choose crops'),
          ),
          const Text(
            'All farms. No distance limit. Saving a farm is optional.',
            style: TextStyle(fontSize: 12, color: AppColors.infoSage),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard({required Widget child}) => PremiumCard(
    child: Material(color: Colors.transparent, child: child),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          const PremiumScreenHeader(
            title: 'Alert settings',
            subtitle: 'Choose what appears in your notifications',
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : ValueListenableBuilder<bool>(
                    valueListenable: isPremium,
                    builder: (context, premium, _) => ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _settingsCard(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Business alerts',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              'Pause or enable the alerts below. Other account notifications are unaffected.',
                            ),
                            value: _settings!.enabled,
                            onChanged: _saving
                                ? null
                                : (v) => setState(
                                    () => _settings = _settings!.copyWith(
                                      enabled: v,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _cropAlertsCard(premium),
                        const SizedBox(height: 12),
                        _settingsCard(
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Saved farm updates'),
                                subtitle: Text(
                                  premium
                                      ? 'New listings and crops becoming Available Now from farms you save.'
                                      : 'Requires premium. Your preference is kept for when you subscribe.',
                                ),
                                value: _settings!.savedFarms,
                                onChanged:
                                    _saving || !_settings!.enabled || !premium
                                    ? null
                                    : (v) => setState(
                                        () => _settings = _settings!.copyWith(
                                          savedFarms: v,
                                        ),
                                      ),
                              ),
                              const Divider(),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Matching buy requests'),
                                subtitle: Text(
                                  SessionState.instance.isSeller
                                      ? 'Buyers requesting crops in your available or upcoming listings.'
                                      : 'For sellers: buyers requesting crops in your available or upcoming listings.',
                                ),
                                value: _settings!.buyRequests,
                                onChanged: _saving || !_settings!.enabled
                                    ? null
                                    : (v) => setState(
                                        () => _settings = _settings!.copyWith(
                                          buyRequests: v,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Tap Save settings to apply your crop choices and switches. Alerts appear in Notifications for future updates; existing listings do not create past alerts.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
          ),
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Save settings'),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
