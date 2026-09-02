import 'package:flutter/material.dart';

import '../../../models/farm_setup_data.dart';
import '../../../services/farm_service.dart';
import '../../../theme.dart';
import 'add_crop_screen.dart';
import 'seller_home_screen.dart';

class FarmSetupCompleteScreen extends StatefulWidget {
  final FarmSetupData farmSetupData;

  const FarmSetupCompleteScreen({super.key, required this.farmSetupData});

  @override
  State<FarmSetupCompleteScreen> createState() =>
      _FarmSetupCompleteScreenState();
}

class _FarmSetupCompleteScreenState extends State<FarmSetupCompleteScreen> {
  bool _isSubmitting = false;
  String? _submitError;

  Future<void> _createFarm() async {
    if (!widget.farmSetupData.isReadyToSubmit) {
      setState(() {
        _submitError = 'Some required farm information is missing. '
            'Please go back and complete the setup steps.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final result = await FarmService.createFarm(widget.farmSetupData);

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SellerHomeScreen()),
        (route) => false,
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
      backgroundColor: AppColors.primaryGreen,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'Farm is Set Up!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'One last thing before you go live',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    _buildSummaryCard(),
                    const Spacer(),
                    const Center(
                      child: Icon(Icons.eco, color: Colors.white, size: 56),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Do you have crops\nready to sell?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'If you have harvest available now or coming soon, you can add your first listing. '
                      'If not, no problem — you can add crops anytime from My Farm.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    if (_submitError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _submitError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _createFarm,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryGreen,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _isSubmitting ? 'Creating your farm...' : 'Create My Farm',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryGreen,
                          disabledBackgroundColor: Colors.white,
                          disabledForegroundColor: AppColors.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AddCropScreen(
                                      isFirstCrop: true,
                                    ),
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Yes, add my first crop now',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => const SellerHomeScreen(),
                                  ),
                                  (route) => false,
                                );
                              },
                        icon: const Icon(
                          Icons.fast_forward,
                          color: Colors.white,
                          size: 16,
                        ),
                        label: const Text(
                          'Skip for now - go to My Farm',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Step 3 of 3',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final location = widget.farmSetupData.latitude != null &&
            widget.farmSetupData.longitude != null
        ? '${widget.farmSetupData.latitude!.toStringAsFixed(6)}, '
            '${widget.farmSetupData.longitude!.toStringAsFixed(6)}'
        : '—';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FARM SUMMARY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'Farm',
            widget.farmSetupData.name.isEmpty
                ? '—'
                : widget.farmSetupData.name,
          ),
          _summaryRow(
            'Barangay',
            widget.farmSetupData.barangay.isEmpty
                ? '—'
                : widget.farmSetupData.barangay,
          ),
          _summaryRow('Location', location),
          _summaryRow('Photos', '${widget.farmSetupData.photos.length}'),
          _summaryRow(
            'Verification',
            widget.farmSetupData.verificationDocument != null
                ? 'Document provided'
                : 'None',
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}