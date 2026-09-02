import 'package:flutter/material.dart';
import '../../../models/farm_setup_data.dart';
import '../../../services/farm_service.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import 'farm_setup_complete_screen.dart';

class FarmSetupLocationScreen extends StatefulWidget {
  final FarmSetupData farmSetupData;

  const FarmSetupLocationScreen({super.key, required this.farmSetupData});

  @override
  State<FarmSetupLocationScreen> createState() =>
      _FarmSetupLocationScreenState();
}

class _FarmSetupLocationScreenState extends State<FarmSetupLocationScreen> {
  static const double _baseLat = 10.3178;
  static const double _baseLng = 123.8742;
  static const double _pxToDegrees = 0.00005;

  Offset _pinOffset = const Offset(0, 0); // relative drag offset from center
  bool _dragged = false;
  String? _errorMessage;
  bool _isSubmitting = false;
  String? _submitError;

  double get _latitude => _baseLat - _pinOffset.dy * _pxToDegrees;

  double get _longitude => _baseLng + _pinOffset.dx * _pxToDegrees;

  Future<void> _confirm() async {
    if (_isSubmitting) return;

    if (!_dragged) {
      setState(() => _errorMessage =
          'Drag the map to pin your farm\'s exact location.');
      return;
    }

    widget.farmSetupData.latitude = _latitude;
    widget.farmSetupData.longitude = _longitude;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _submitError = null;
    });

    final result = await FarmService.createFarm(widget.farmSetupData);

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              FarmSetupCompleteScreen(farmSetupData: widget.farmSetupData),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = false;
      _submitError = result['message'] as String? ?? 'Something went wrong.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SetupHeader(
              title: 'Pin Your Farm',
              subtitle: 'Drag map to pin your farm\'s exact location',
            ),
            const StepProgress(
              step: 3,
              totalSteps: 3,
              label: 'Location',
              percent: 0.95,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _pinOffset += details.delta;
                              _dragged = true;
                              _errorMessage = null;
                            });
                          },
                          child: Container(
                            color: const Color(0xFFE8ECE6),
                            child: Stack(
                              children: [
                                CustomPaint(
                                  size: Size.infinite,
                                  painter: _FakeMapPainter(),
                                ),
                                Center(
                                  child: Transform.translate(
                                    offset: _pinOffset,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.redAccent,
                                      size: 44,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Text(
                                        'Drag to adjust your location',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: AppColors.primaryGreen,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sudlon dos. Maraag',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  _dragged
                                      ? '${_latitude.toStringAsFixed(6)}, '
                                          '${_longitude.toStringAsFixed(6)}'
                                      : 'GPS detected, drag to adjust',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_submitError != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _submitError!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _confirm,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryGreen,
                                ),
                              )
                            : const Icon(Icons.check),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.primaryGreen,
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        label: Text(
                          _isSubmitting
                              ? 'Creating your farm...'
                              : 'Create My Farm',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Step 3 of 3',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.black38),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FakeMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height * 0.35),
      Offset(size.width, size.height * 0.3),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.25, 0),
      Offset(size.width * 0.4, size.height),
      paint,
    );
    final water = Paint()..color = const Color(0xFFB9D8E8);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 30, water);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}