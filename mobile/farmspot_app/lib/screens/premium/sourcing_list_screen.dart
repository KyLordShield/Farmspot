import '../../widgets/lottie_loader.dart';
import 'package:flutter/material.dart';
import '../../services/sourcing_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/premium_widgets.dart';
import 'sourcing_trip_screen.dart';
import '../../widgets/sourcing_crop_picker.dart';

class SourcingListScreen extends StatefulWidget {
  final SourcingGateway? gateway;
  const SourcingListScreen({super.key, this.gateway});

  @override
  State<SourcingListScreen> createState() => _SourcingListScreenState();
}

class _SourcingListScreenState extends State<SourcingListScreen> {
  final Set<String> _crops = {};
  List<String> _catalog = [];
  Map<String, List<String>> _aliases = {};
  bool _loading = true, _saving = false;
  String? _error;
  SourcingGateway get _gateway => widget.gateway ?? SourcingService.instance;
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
      final list = await _gateway.fetchList();
      if (!mounted) return;
      setState(() {
        _crops
          ..clear()
          ..addAll(list.crops);
        _catalog = {...list.availableCrops, ...list.crops}.toList()..sort();
        _aliases = list.aliases;
        _loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  Future<void> _save({bool find = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await withFarmLottieLoading(
        context,
        () => _gateway.saveList(_crops.toList()..sort()),
        message: 'Saving your weekly list...',
      );
      if (!mounted) return;
      if (find) {
        pushPremiumScreen(context, SourcingTripScreen(gateway: _gateway));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Weekly list saved.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleCrop(String crop) {
    setState(() {
      if (_crops.contains(crop)) {
        _crops.remove(crop);
      } else {
        _crops.add(crop);
      }
    });
  }

  Future<void> _addCrops() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SourcingCropPicker(
        catalog: _catalog,
        aliases: _aliases,
        selected: _crops,
      ),
    );
    if (selected != null && mounted)
      setState(() {
        _crops
          ..clear()
          ..addAll(selected);
      });
  }

  void _findTrip() {
    if (_crops.isEmpty) {
      showFarmAlert(
        context,
        type: FarmAlertType.warning,
        title: 'Add crops first',
        message: 'Pick at least one crop for your weekly list.',
      );
      return;
    }
    _save(find: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const PremiumScreenHeader(
              title: 'Weekly Sourcing List',
              subtitle: 'Find farms growing the crops you need',
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: FarmLottieLoading(
                        message: 'Loading your weekly list...',
                      ),
                    )
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
                  : AbsorbPointer(
                      absorbing: _saving,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          PremiumCard(
                            background: AppColors.infoSoft,
                            borderColor: AppColors.infoSage.withValues(
                              alpha: 0.25,
                            ),
                            child: const Text(
                              'Add the crops you need this week. See all matching farms, sorted from nearest to farthest.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.infoSage,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const SectionHeader(title: 'YOUR LIST'),
                          const SizedBox(height: 8),
                          if (_crops.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No crops yet. Tap Add crops to build your weekly list.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black54),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final c in _crops.toList()..sort())
                                  InputChip(
                                    label: Text(c),
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 16,
                                    ),
                                    onDeleted: () => _toggleCrop(c),
                                    backgroundColor: AppColors.successSoft,
                                    side: BorderSide(
                                      color: AppColors.primaryGreen.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _addCrops,
                            icon: const Icon(Icons.add),
                            label: const Text('Add crops'),
                          ),
                          Text(
                            '${_crops.length} of 50 crops selected',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const PremiumCard(
                            background: AppColors.infoSoft,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.near_me_outlined,
                                  color: AppColors.infoSage,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Nearest farms first. All matching farms are included, with no distance limit.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: AppColors.infoSage,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            if (!_loading && _error == null)
              TextButton(
                onPressed: _saving ? null : () => _save(),
                child: const Text('Save list'),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FarmSpotButton(
                label: _saving ? 'Saving list...' : 'Find matching farms',
                onPressed: () {
                  if (!_loading && !_saving && _error == null) _findTrip();
                },
                trailingIcon: Icons.search,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
