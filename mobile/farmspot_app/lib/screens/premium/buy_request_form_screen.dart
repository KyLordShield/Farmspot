import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../models/buy_request.dart';
import '../../models/crop_choice.dart';
import 'buy_request_pin_screen.dart';
import '../../services/buy_request_service.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/premium_widgets.dart';

class BuyRequestFormScreen extends StatefulWidget {
  final BuyRequestsGateway? gateway;
  const BuyRequestFormScreen({super.key, this.gateway});
  @override
  State<BuyRequestFormScreen> createState() => _BuyRequestFormScreenState();
}

class _BuyRequestFormScreenState extends State<BuyRequestFormScreen> {
  final _crop = TextEditingController();
  final _qty = TextEditingController(text: '15');
  final _note = TextEditingController();
  final _pickup = TextEditingController();
  String _frequency = 'weekly';
  bool _busy = false, _loadingCrops = true;
  List<CropChoice> _choices = [];
  String? _selectedCrop, _cropError;
  LatLng? _position;
  String? _error;
  @override
  void initState() {
    super.initState();
    _loadCrops();
  }

  Future<void> _loadCrops() async {
    try {
      final choices = await (widget.gateway ?? BuyRequestService.instance)
          .fetchCrops();
      if (mounted)
        setState(() {
          _choices = choices;
          _loadingCrops = false;
          _cropError = null;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingCrops = false;
          _cropError = 'Could not load crops. Please retry.';
        });
    }
  }

  @override
  void dispose() {
    _crop.dispose();
    _qty.dispose();
    _note.dispose();
    _pickup.dispose();
    super.dispose();
  }

  Future<void> _pickPin() async {
    final pin = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => BuyRequestPinScreen(initialPin: _position),
      ),
    );
    if (pin != null && mounted) setState(() => _position = pin);
  }

  Future<void> _post() async {
    if (_busy) return;
    if (_selectedCrop == null || _crop.text != _selectedCrop) {
      setState(
        () => _error =
            'Choose a crop from the suggestions before posting. Put descriptions in the note.',
      );
      return;
    }
    final quantity = double.tryParse(_qty.text.trim());
    if (_crop.text.trim().isEmpty ||
        quantity == null ||
        !quantity.isFinite ||
        quantity < 0.01 ||
        quantity > 99999999.99 ||
        !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(_qty.text.trim())) {
      setState(
        () => _error =
            'Enter a crop and a quantity of at least 0.01 kg, with up to two decimal places.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await (widget.gateway ?? BuyRequestService.instance).create(
        crop: _selectedCrop!,
        quantityKg: quantity,
        frequency: _frequency,
        note: _note.text.trim(),
        pickupLocation: _pickup.text.trim(),
        latitude: _position?.latitude,
        longitude: _position?.longitude,
      );
      if (!mounted) return;
      Navigator.of(context).pop<BuyRequest>(row);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _busy = false;
        });
    }
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          const PremiumScreenHeader(
            title: 'New Buy Request',
            subtitle: 'Let all approved sellers discover what you need',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                _label('What crop do you need?'),
                TextField(
                  controller: _crop,
                  maxLength: 80,
                  onChanged: (_) => setState(() {
                    _selectedCrop = null;
                    _error = null;
                  }),
                  decoration: const InputDecoration(
                    hintText: 'Search a crop, e.g. cabbge',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Text(
                  'Choose the crop name below. Put business needs and other details in the note.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (_loadingCrops) const LinearProgressIndicator(),
                if (_cropError != null)
                  TextButton(onPressed: _loadCrops, child: Text(_cropError!)),
                if (!_loadingCrops &&
                    _cropError == null &&
                    suggestCrops(_crop.text, _choices).isEmpty)
                  const Text(
                    'No matching crop. Try another spelling.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.errorTerracotta,
                    ),
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final choice in suggestCrops(_crop.text, _choices))
                      ChoiceChip(
                        label: Text(choice.name),
                        selected: _selectedCrop == choice.name,
                        onSelected: (_) => setState(() {
                          _selectedCrop = choice.name;
                          _crop.text = choice.name;
                          _error = null;
                        }),
                      ),
                  ],
                ),
                if (_selectedCrop != null)
                  Text(
                    'Selected crop: $_selectedCrop',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                _label('Quantity (kg)'),
                TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'e.g. 15',
                    border: OutlineInputBorder(),
                  ),
                ),
                _label('How often?'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in ['one-time', 'weekly'])
                      ChoiceChip(
                        label: Text(value == 'weekly' ? 'Weekly' : 'One-time'),
                        selected: _frequency == value,
                        onSelected: (_) => setState(() => _frequency = value),
                      ),
                  ],
                ),
                _label('Pickup or delivery preference (optional)'),
                TextField(
                  controller: _pickup,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Can collect in Sudlon / delivery preferred',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Text(
                  'This is information for sellers, not a distance restriction.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                _label('Map pin (optional)'),
                const Text(
                  'Add a map pin only if you want sellers to see your exact location. Without a pin, sellers will see “No location shared”.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.black54,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickPin,
                      icon: const Icon(
                        Icons.add_location_alt_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _position == null
                            ? 'Pin location on map'
                            : 'Change map pin',
                      ),
                    ),
                    if (_position != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _position = null),
                        child: const Text('Remove pin'),
                      ),
                  ],
                ),
                if (_position != null)
                  const Text(
                    'Map pin added. It will be shared when you post this request.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Your profile phone number is shared with approved sellers so they can call using their phone app.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                _label('Note for sellers (optional)'),
                TextField(
                  controller: _note,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Prefer morning pickup',
                    border: OutlineInputBorder(),
                  ),
                ),
                const PremiumCard(
                  background: AppColors.successSoft,
                  child: Text(
                    'Your request stays posted until you remove it. Sellers can message you to discuss supply, price, and pickup. There is no expiry or distance limit.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.darkGreen,
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.errorTerracotta),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: IgnorePointer(
              ignoring: _busy || _loadingCrops,
              child: FarmSpotButton(
                label: _busy ? 'Posting...' : 'Post request',
                onPressed: _post,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
