import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import 'farm_setup_location_screen.dart';

class FarmSetupVerifyScreen extends StatefulWidget {
  const FarmSetupVerifyScreen({super.key});

  @override
  State<FarmSetupVerifyScreen> createState() => _FarmSetupVerifyScreenState();
}

class _FarmSetupVerifyScreenState extends State<FarmSetupVerifyScreen> {
  final _fullNameCtrl = TextEditingController();
  bool _idUploaded = true; // placeholder — mimics reference screenshot
  bool _proofUploaded = false;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    super.dispose();
  }

  void _next() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FarmSetupLocationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SetupHeader(
              title: 'Verify Identity',
              subtitle: 'For trust & community safety',
            ),
            const StepProgress(
              step: 2,
              totalSteps: 3,
              label: 'Verification',
              percent: 0.66,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  const FieldLabel('VALID ID', badge: '*REQUIRED'),
                  UploadBox(
                    icon: Icons.badge_outlined,
                    title: 'Barangay ID',
                    subtitle: _idUploaded
                        ? 'Uploaded id.front.jpg'
                        : 'Upload a valid government/barangay ID',
                    buttonLabel: _idUploaded ? 'Change' : 'Upload',
                    onTap: () => setState(() => _idUploaded = true),
                  ),
                  const SizedBox(height: 20),
                  const FieldLabel('PROOF OF FARMING', badge: '(optional)', badgeColor: Colors.black38),
                  UploadBox(
                    icon: Icons.description_outlined,
                    title: 'Farm Certificate/Photo',
                    subtitle: _proofUploaded
                        ? 'Uploaded certificate.jpg'
                        : 'Upload proof of your farm or plot',
                    buttonLabel: _proofUploaded ? 'Change' : 'Upload',
                    onTap: () => setState(() => _proofUploaded = true),
                  ),
                  const SizedBox(height: 20),
                  const FieldLabel('SELLER FULL NAME'),
                  TextField(
                    controller: _fullNameCtrl,
                    decoration: InputDecoration(
                      hintText: 'Full name as on ID',
                      hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.fieldBackground,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primaryGreen),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.primaryGreen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  WizardNextButton(
                    label: 'Next: Pin Farm Location',
                    onPressed: _next,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Step 2 of 3',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.black38),
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
