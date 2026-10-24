import 'package:flutter/material.dart';
import '../../premium/premium_mock_data.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/premium_widgets.dart';

class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key});

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _type = kBusinessTypes.first;
  bool _permitPicked = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _addressCtrl.text.trim().isEmpty) {
      await showFarmAlert(
        context,
        type: FarmAlertType.warning,
        title: 'Missing details',
        message: 'Please enter your business name and address.',
      );
      return;
    }
    await showFarmAlert(
      context,
      type: FarmAlertType.success,
      title: 'Submitted for review',
      message:
          'Our team verifies your business to give you the Verified Business badge. This usually takes 1–2 business days.',
      buttonLabel: 'Done',
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const PremiumScreenHeader(
              title: 'Set up your business',
              subtitle: 'Needed for the Verified Business badge',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  StatusChip.pending(),
                  const SizedBox(height: 12),
                  PremiumCard(
                    background: AppColors.infoSoft,
                    borderColor: AppColors.infoSage.withValues(alpha: 0.25),
                    child: const Text(
                      'Our team verifies your business to give you the Verified Business badge. Farmers see this when you send Buy Requests.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.infoSage,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Business name',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  FarmSpotTextField(
                    hint: 'e.g. Carinderia ni Nanay Rosa',
                    controller: _nameCtrl,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Business type',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.fieldBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.fieldBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _type,
                        isExpanded: true,
                        items: [
                          for (final t in kBusinessTypes)
                            DropdownMenuItem(value: t, child: Text(t)),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _type = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Business address',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  FarmSpotTextField(
                    hint: 'Street, barangay, Cebu City',
                    controller: _addressCtrl,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Business permit (optional)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  PremiumCard(
                    onTap: () => setState(() => _permitPicked = true),
                    child: Row(
                      children: [
                        Icon(
                          _permitPicked
                              ? Icons.check_circle
                              : Icons.upload_file_outlined,
                          color: _permitPicked
                              ? AppColors.primaryGreen
                              : Colors.black45,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _permitPicked
                                ? 'permit_photo.jpg selected (preview)'
                                : 'Tap to upload a photo of your permit',
                            style: TextStyle(
                              fontSize: 13,
                              color: _permitPicked
                                  ? AppColors.darkGreen
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FarmSpotButton(
                    label: 'Submit for verification',
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
