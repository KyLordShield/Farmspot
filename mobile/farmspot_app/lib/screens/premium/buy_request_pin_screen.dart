import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import '../../widgets/map_tile_layer.dart';
import '../../widgets/premium_widgets.dart';

class BuyRequestPinScreen extends StatefulWidget {
  final LatLng? initialPin;
  final bool readOnly;
  final Widget? tileLayer;
  const BuyRequestPinScreen({
    super.key,
    this.initialPin,
    this.readOnly = false,
    this.tileLayer,
  });
  @override
  State<BuyRequestPinScreen> createState() => _BuyRequestPinScreenState();
}

class _BuyRequestPinScreenState extends State<BuyRequestPinScreen> {
  final _map = MapController();
  late LatLng? _pin = widget.initialPin;
  bool _locating = false;
  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    final point = await LocationService.tryBuyerPosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (point != null) _pin = point;
    });
    if (point != null) {
      _map.move(point, 16);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location unavailable. Tap the map to place your pin instead.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          PremiumScreenHeader(
            title: widget.readOnly ? 'Buyer location' : 'Pin your location',
            subtitle: widget.readOnly
                ? 'Location shared by the buyer'
                : 'Tap the map, then confirm the pin',
          ),
          if (!widget.readOnly)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Optional: approved sellers will see the exact pin you confirm. You can go back without adding a location.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _pin ?? LocationService.fallbackPosition,
                    initialZoom: 15,
                    onTap: widget.readOnly
                        ? null
                        : (_, point) => setState(() => _pin = point),
                  ),
                  children: [
                    widget.tileLayer ?? const MapTileLayer(),
                    if (_pin != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pin!,
                            width: 48,
                            height: 48,
                            child: const Icon(
                              Icons.location_pin,
                              color: AppColors.errorTerracotta,
                              size: 44,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (!widget.readOnly)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      tooltip: 'Use my location',
                      onPressed: _locating ? null : _locate,
                      child: _locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _pin == null
                      ? 'No pin selected. Tap the map to choose a location.'
                      : '${_pin!.latitude.toStringAsFixed(6)}, ${_pin!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('confirm-request-pin'),
                    onPressed: widget.readOnly
                        ? () => Navigator.pop(context)
                        : (_pin == null
                              ? null
                              : () => Navigator.pop(context, _pin)),
                    child: Text(
                      widget.readOnly ? 'Back to requests' : 'Use this pin',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
