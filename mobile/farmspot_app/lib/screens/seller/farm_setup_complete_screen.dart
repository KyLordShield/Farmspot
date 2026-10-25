import 'package:flutter/material.dart';

import '../../../models/farm_setup_data.dart';
import '../../../theme.dart';
import '../profile_screen.dart';
import 'add_crop_screen.dart';
import '../home_screen.dart';

class FarmSetupCompleteScreen extends StatelessWidget {
  final FarmSetupData farmSetupData;
  final String frmStatus;
  final String? farmId;
  final bool isAdditionalFarm;

  const FarmSetupCompleteScreen({
    super.key,
    required this.farmSetupData,
    this.farmId,
    this.frmStatus = 'APPROVED',
    this.isAdditionalFarm = false,
  });

  bool get _isPending => frmStatus == 'PENDING_REVIEW';

  String get _location {
    final address = farmSetupData.locationAddress?.trim() ?? '';
    if (address.isNotEmpty) return address;
    final barangay = farmSetupData.barangay.trim();
    return barangay.isNotEmpty ? barangay : 'Map pin saved';
  }

  String get _verificationSummary {
    final count =
        (farmSetupData.verificationDocument != null ? 1 : 0) +
        (farmSetupData.farmCertificate != null ? 1 : 0);
    if (count == 2) return '2 documents provided';
    if (count == 1) return '1 document provided';
    return isAdditionalFarm
        ? 'Reused from your first farm'
        : 'No documents provided';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        color: AppColors.successSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: AppColors.primaryGreen,
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isPending
                        ? 'Thanks for submitting!'
                        : 'Your farm is set up!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isPending
                        ? 'We received your farm application. Our team will review your details and documents.'
                        : 'Your farm is ready. Start sharing what you grow with nearby buyers.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFF59645B),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.infoSoft,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _isPending
                              ? Icons.notifications_outlined
                              : Icons.eco_outlined,
                          color: AppColors.primaryGreen,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isPending
                                    ? 'What happens next?'
                                    : 'Have crops ready to sell?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkGreen,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isPending
                                    ? "We'll notify you once your farm is approved. You can start listing crops after approval."
                                    : 'Add your first crop now, or come back anytime from My Farm.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: Color(0xFF59645B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      if (_isPending) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                          (route) => false,
                        );
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AddCropScreen(
                              isFirstCrop: true,
                              farmId: farmId,
                            ),
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      _isPending ? Icons.person_outline : Icons.add_rounded,
                    ),
                    label: Text(
                      _isPending ? 'Back to My Profile' : 'Add a crop',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!_isPending) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                      ),
                      child: const Text('Skip for now - go to Home'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E8DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Farm summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _isPending
                    ? AppColors.warningSoft
                    : AppColors.successSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _isPending ? 'Pending review' : 'Ready to list crops',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _isPending
                      ? AppColors.warningAmber
                      : AppColors.primaryGreen,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFEDF0EB)),
          _summaryRow(
            Icons.agriculture_outlined,
            'Farm name',
            farmSetupData.name.trim().isEmpty
                ? 'Your farm'
                : farmSetupData.name.trim(),
          ),
          _summaryRow(Icons.location_on_outlined, 'Location', _location),
          _summaryRow(
            Icons.photo_library_outlined,
            'Farm photos',
            '${farmSetupData.photos.length} ${farmSetupData.photos.length == 1 ? 'photo' : 'photos'} added',
          ),
          _summaryRow(
            Icons.verified_user_outlined,
            'Verification',
            _verificationSummary,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: AppColors.mutedGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF69746B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF253D2A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
