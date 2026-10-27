import '../../widgets/lottie_loader.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'buy_request_pin_screen.dart';
import '../../models/buy_request.dart';
import '../../models/conversation.dart';
import '../../services/buy_request_service.dart';
import '../../premium/premium_state.dart';
import '../../premium/premium_nav.dart';
import '../../theme.dart';
import '../../widgets/premium_widgets.dart';
import '../in_app_messages_screen.dart';
import 'buy_request_form_screen.dart';

class MyRequestsScreen extends StatefulWidget {
  final BuyRequestsGateway? gateway;
  const MyRequestsScreen({super.key, this.gateway});
  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  BuyRequestsGateway get _api => widget.gateway ?? BuyRequestService.instance;
  List<BuyRequest> _requests = [];
  bool _loading = true;
  String? _error;
  final Set<String> _removing = {};
  final Set<String> _responsesLoading = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.fetchMine();
      if (!mounted) return;
      setState(() {
        _requests = rows;
        _error = null;
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

  Future<void> _newRequest() async {
    if (!isPremium.value) {
      await openUpgrade(context);
      if (!mounted || !isPremium.value) return;
    }
    final created = await Navigator.of(context).push<BuyRequest>(
      MaterialPageRoute(builder: (_) => BuyRequestFormScreen(gateway: _api)),
    );
    if (created != null && mounted) await _load();
  }

  Future<void> _editRequest(BuyRequest request) async {
    if (!isPremium.value) {
      await openUpgrade(context);
      if (!mounted || !isPremium.value) return;
    }
    final saved = await Navigator.of(context).push<BuyRequest>(
      MaterialPageRoute(
        builder: (_) => BuyRequestFormScreen(gateway: _api, request: request),
      ),
    );
    if (saved != null && mounted) await _load();
  }

  Future<void> _removeRequest(BuyRequest request) async {
    if (_removing.contains(request.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove request?'),
        content: Text(
          'Remove your ${request.crop} request from the seller board? Existing messages will remain in your inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep request'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.errorTerracotta),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing.add(request.id));
    try {
      await withFarmLottieLoading(
        context,
        () => _api.remove(request.id),
        message: 'Removing your request...',
      );
      if (mounted)
        setState(() => _requests.removeWhere((r) => r.id == request.id));
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _removing.remove(request.id));
    }
  }

  void _showError(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
  );
  Future<void> _viewResponses(BuyRequest request) async {
    if (_responsesLoading.contains(request.id)) return;
    setState(() => _responsesLoading.add(request.id));
    try {
      final threads = await withFarmLottieLoading(
        context,
        () => _api.fetchResponses(request.id),
        message: 'Loading seller responses...',
      );
      if (!mounted) return;
      final selected = await showModalBottomSheet<Conversation>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 400,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Seller conversations · ${request.crop}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: threads.isEmpty
                      ? const Center(
                          child: Text('No sellers have contacted you yet.'),
                        )
                      : ListView(
                          children: [
                            for (final thread in threads)
                              ListTile(
                                leading: const Icon(Icons.chat_bubble_outline),
                                title: Text(thread.otherPartyName ?? 'Seller'),
                                subtitle: Text(
                                  thread.lastMessage ??
                                      'Start discussing supply and pickup',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.pop(ctx, thread),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected != null && mounted)
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InAppMessagesScreen(conversation: selected),
          ),
        );
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _responsesLoading.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          const PremiumScreenHeader(
            title: 'My Buy Requests',
            subtitle: 'Visible to approved sellers while Premium is active',
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: PremiumCard(
              background: AppColors.successSoft,
              child: Text(
                'Requests stay saved until you remove them. If Premium expires, they are hidden from sellers and reappear when you renew. Existing messages remain available.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.darkGreen,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: FarmLottieLoading(
                      message: 'Loading your requests...',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.errorTerracotta,
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        ],
                        if (_requests.isEmpty && _error == null)
                          PremiumEmptyState(
                            icon: Icons.campaign_outlined,
                            title: 'What does your business need?',
                            message:
                                'Post a request so sellers can offer their produce.',
                            actionLabel: 'New request',
                            onAction: _newRequest,
                          ),
                        for (final r in _requests) ...[
                          IgnorePointer(
                            ignoring: _removing.contains(r.id),
                            child: RequestCard(
                              crop: r.crop,
                              quantityLabel: r.quantityLabel,
                              frequencyLabel: r.frequencyLabel,
                              pickupLabel: r.pickupLocation.isEmpty
                                  ? 'Pickup arrangements discussed in Messages'
                                  : r.pickupLocation,
                              note: r.note,
                              updatedAt: r.updatedAt,
                              onEdit: () => _editRequest(r),
                              onRemove: () => _removeRequest(r),
                              responseCount: r.responseCount,
                              busy: _responsesLoading.contains(r.id),
                              onViewResponses: () => _viewResponses(r),
                              hasPin: r.hasPin,
                              onViewPin: r.hasPin
                                  ? () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => BuyRequestPinScreen(
                                          initialPin: LatLng(
                                            r.latitude!,
                                            r.longitude!,
                                          ),
                                          readOnly: true,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _newRequest,
      backgroundColor: AppColors.primaryGreen,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: const Text('New request'),
    ),
  );
}
