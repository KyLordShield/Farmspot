import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/farm_setup_data.dart';
import '../../../services/auth_service.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import 'farm_setup_location_screen.dart';

class FarmSetupVerifyScreen extends StatefulWidget {
  final FarmSetupData farmSetupData;

  const FarmSetupVerifyScreen({super.key, required this.farmSetupData});

  @override
  State<FarmSetupVerifyScreen> createState() => _FarmSetupVerifyScreenState();
}

class _FarmSetupVerifyScreenState extends State<FarmSetupVerifyScreen> {
  final _picker = ImagePicker();
  final _fullNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prefillSellerName();
  }

  /// Uses the name already persisted at login/registration — no extra
  /// GET /api/user call needed (AuthService.getUser reads local storage).
  Future<void> _prefillSellerName() async {
    final user = await AuthService.getUser();
    if (!mounted) return;
    final name = (user?['USR_NAME'] as String? ?? '').trim();
    if (name.isNotEmpty) {
      setState(() => _fullNameCtrl.text = name);
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    super.dispose();
  }

  XFile? get _proofDocument => widget.farmSetupData.verificationDocument;

  String get _proofSubtitle {
    final doc = _proofDocument;
    if (doc == null) return 'Upload a valid ID or proof of your farm/plot';
    return 'Uploaded ${doc.name}';
  }

  Future<void> _pickProofDocument() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo Library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _picker.pickImage(source: source);
    if (picked != null && mounted) {
      setState(() => widget.farmSetupData.verificationDocument = picked);
    }
  }

  void _next() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FarmSetupLocationScreen(farmSetupData: widget.farmSetupData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasProof = _proofDocument != null;
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
                  const FieldLabel(
                    'VALID ID OR FARM CERTIFICATE',
                    badge: '(optional)',
                    badgeColor: Colors.black38,
                  ),
                  UploadBox(
                    icon: Icons.badge_outlined,
                    title: 'Barangay ID',
                    subtitle: _proofSubtitle,
                    buttonLabel: hasProof ? 'Change' : 'Upload',
                    onTap: _pickProofDocument,
                  ),
                  const SizedBox(height: 20),
                  UploadBox(
                    icon: Icons.description_outlined,
                    title: 'Farm Certificate/Photo',
                    subtitle: _proofSubtitle,
                    buttonLabel: hasProof ? 'Change' : 'Upload',
                    onTap: _pickProofDocument,
                  ),
                  const SizedBox(height: 20),
                  const FieldLabel('SELLER FULL NAME'),
                  TextField(
                    controller: _fullNameCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Full name as on ID',
                      hintStyle: const TextStyle(
                        color: Colors.black38,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: AppColors.fieldBackground,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.primaryGreen,
                        ),
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