import 'package:flutter/material.dart';
import '../premium/premium_nav.dart';
import '../premium/premium_state.dart';
import '../services/saved_farms_state.dart';
import '../theme.dart';

class SaveFarmButton extends StatefulWidget {
  final String farmId;
  final SavedFarmsState? savedFarms;
  final Color? color;
  const SaveFarmButton({
    super.key,
    required this.farmId,
    this.savedFarms,
    this.color,
  });
  @override
  State<SaveFarmButton> createState() => _SaveFarmButtonState();
}

class _SaveFarmButtonState extends State<SaveFarmButton> {
  SavedFarmsState get _saved => widget.savedFarms ?? SavedFarmsState.instance;
  @override
  void initState() {
    super.initState();
    isPremium.addListener(_premiumChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _premiumChanged() {
    if (isPremium.value) Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted || !isPremium.value) return;
    try {
      await _saved.load();
    } catch (_) {
      /* A tap retries and surfaces errors. */
    }
  }

  Future<void> _toggle() async {
    if (_saved.isBusy(widget.farmId)) return;
    if (!isPremium.value) {
      await openUpgrade(context);
      if (!mounted || !isPremium.value) return;
    }
    try {
      final saved = await _saved.toggle(widget.farmId);
      if (!mounted) return;
      _showMessage(
        saved ? 'Farm saved to Saved Farms.' : 'Farm removed from Saved Farms.',
      );
    } catch (e) {
      if (mounted) _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    isPremium.removeListener(_premiumChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_saved, isPremium]),
    builder: (context, _) => IconButton(
      onPressed: _saved.isBusy(widget.farmId) ? null : _toggle,
      tooltip: _saved.isSaved(widget.farmId) ? 'Unsave farm' : 'Save farm',
      icon: _saved.isBusy(widget.farmId)
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              _saved.isSaved(widget.farmId)
                  ? Icons.favorite
                  : Icons.favorite_border,
            ),
      color: widget.color ?? AppColors.premiumGold,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    ),
  );
}
