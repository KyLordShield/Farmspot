import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import 'farm_setup_verify_screen.dart';

class FarmSetupDetailsScreen extends StatefulWidget {
  const FarmSetupDetailsScreen({super.key});

  @override
  State<FarmSetupDetailsScreen> createState() => _FarmSetupDetailsScreenState();
}

class _FarmSetupDetailsScreenState extends State<FarmSetupDetailsScreen> {
  final _farmNameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  int _photoCount = 0;

  @override
  void dispose() {
    _farmNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _barangayCtrl.dispose();
    super.dispose();
  }

  void _addPhoto() {
    if (_photoCount < 4) setState(() => _photoCount++);
  }

  void _next() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FarmSetupVerifyScreen()),
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
              title: 'Set Up Your Farm',
              subtitle: 'Tell buyers about your farm',
            ),
            const StepProgress(
              step: 1,
              totalSteps: 3,
              label: 'Farm Details',
              percent: 0.33,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  const FieldLabel('FARM NAME'),
                  TextField(
                    controller: _farmNameCtrl,
                    decoration: _inputDecoration(),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('DESCRIPTION'),
                  TextField(
                    controller: _descriptionCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: _inputDecoration(),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('BARANGAY'),
                  TextField(
                    controller: _barangayCtrl,
                    decoration: _inputDecoration(),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('FARM PHOTOS'),
                  SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (int i = 0; i < _photoCount; i++) ...[
                          const PhotoPlaceholder(),
                          const SizedBox(width: 10),
                        ],
                        PhotoPlaceholder(isAddButton: true, onTap: _addPhoto),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  WizardNextButton(
                    label: 'Next: Verify Identity',
                    onPressed: _next,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Step 1 of 3',
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

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.fieldBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryGreen),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryGreen),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
      ),
    );
  }
}
