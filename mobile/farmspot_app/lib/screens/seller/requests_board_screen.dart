import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../premium/buy_request_pin_screen.dart';
import '../../models/buy_request.dart';
import '../../services/buy_request_service.dart';
import '../../theme.dart';
import '../../widgets/buy_request_widgets.dart';
import '../../widgets/premium_widgets.dart';
import '../in_app_messages_screen.dart';

class RequestsBoardScreen extends StatefulWidget {
  final BuyRequestsGateway? gateway;
  final Future<bool> Function(Uri)? externalCallLauncher;
  const RequestsBoardScreen({
    super.key,
    this.gateway,
    this.externalCallLauncher,
  });
  @override
  State<RequestsBoardScreen> createState() => _RequestsBoardScreenState();
}

class _RequestsBoardScreenState extends State<RequestsBoardScreen> {
  BuyRequestsGateway get _api => widget.gateway ?? BuyRequestService.instance;
  List<BuyRequest> _requests = [];
  final _search = TextEditingController();
  final Set<String> _opening = {};
  bool _loading = true;
  String? _error;
  int _loadVersion = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final rows = await _api.fetchBoard(search: _search.text);
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _requests = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && version == _loadVersion)
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  Future<void> _message(BuyRequest request) async {
    if (_opening.contains(request.id)) return;
    setState(() => _opening.add(request.id));
    try {
      final thread = await _api.contactBuyer(request.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InAppMessagesScreen(conversation: thread),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
    } finally {
      if (mounted) setState(() => _opening.remove(request.id));
    }
  }

  String _phone(BuyRequest request) =>
      request.buyerPhone.replaceAll(RegExp(r'[^0-9+]'), '');
  bool _canCall(BuyRequest request) =>
      RegExp(r'^\+?[0-9]{7,15}$').hasMatch(_phone(request));
  Future<void> _call(BuyRequest request) async {
    final uri = Uri(scheme: 'tel', path: _phone(request));
    try {
      final opened = await (widget.externalCallLauncher != null
          ? widget.externalCallLauncher!(uri)
          : launchUrl(uri, mode: LaunchMode.externalApplication));
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open your phone app. You can message the buyer instead.',
          ),
        ),
      );
  }

  void _showPin(BuyRequest r) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BuyRequestPinScreen(
        initialPin: LatLng(r.latitude!, r.longitude!),
        readOnly: true,
      ),
    ),
  );

  Widget _contactActions(BuyRequest r) {
    final message = FilledButton.icon(
      onPressed: _opening.contains(r.id) ? null : () => _message(r),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryGreen,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
      label: Text(
        _opening.contains(r.id) ? 'Opening...' : 'Message buyer',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
      ),
    );
    final call = OutlinedButton.icon(
      onPressed: _canCall(r) ? () => _call(r) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryGreen,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        side: const BorderSide(color: Color(0xFFCCDACA)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      icon: const Icon(Icons.call_outlined, size: 17),
      label: const Text('Call buyer', style: TextStyle(fontSize: 12)),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 250 ||
            MediaQuery.textScalerOf(context).scale(14) > 17) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [message, const SizedBox(height: 8), call],
          );
        }
        return Row(
          children: [
            Expanded(flex: 6, child: message),
            const SizedBox(width: 8),
            Expanded(flex: 4, child: call),
          ],
        );
      },
    );
  }

  Widget _requestCard(BuyRequest r) => PremiumCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                r.crop,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkGreen,
                ),
              ),
            ),
            const SizedBox(width: 8),
            RequestPill(r.quantityLabel, highlighted: true),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '${r.buyerName} · ${r.frequencyLabel}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        if (r.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          RequestNote(r.note),
        ],
        if (r.pickupLocation.isNotEmpty) ...[
          const SizedBox(height: 5),
          RequestNote('Pickup / delivery: ${r.pickupLocation}'),
        ],
        const SizedBox(height: 5),
        if (r.hasPin)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              if (r.distanceKm != null)
                Text(
                  'About ${r.distanceKm!.toStringAsFixed(1)} km from your farm',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedGreen,
                  ),
                ),
              TextButton.icon(
                onPressed: () => _showPin(r),
                icon: const Icon(Icons.location_on_outlined, size: 15),
                label: const Text(
                  'View map pin',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  minimumSize: const Size(44, 40),
                ),
              ),
            ],
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No location shared',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
        const SizedBox(height: 5),
        _contactActions(r),
        if (!_canCall(r))
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Text(
              'No phone number available. You can still message the buyer.',
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: Colors.black45,
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          const PremiumScreenHeader(
            title: 'Buyer Requests',
            subtitle: 'Find buyers looking for your produce',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search by crop',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Search requests',
                  onPressed: _load,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'All requests · nearest pinned locations first · no distance limit',
              style: TextStyle(fontSize: 12, color: AppColors.mutedGreen),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
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
                          const PremiumEmptyState(
                            icon: Icons.campaign_outlined,
                            title: 'No matching buyer requests',
                            message:
                                'Requests appear here when buyers post what they need. Try another crop or check back later.',
                          ),
                        for (final r in _requests) ...[
                          _requestCard(r),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
