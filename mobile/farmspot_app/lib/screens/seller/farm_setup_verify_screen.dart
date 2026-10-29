import '../../legal/legal.dart';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';

import '../../../models/farm_setup_data.dart';
import '../../../services/auth_service.dart';
import '../../../services/document_text_check.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import 'farm_setup_location_screen.dart';
import 'document_capture_screen.dart';

class FarmSetupVerifyScreen extends StatefulWidget {
  final FarmSetupData farmSetupData;
  final Future<String> Function(XFile) readDocument;
  final Future<XFile?> Function()? captureDocument;
  final Future<bool> Function()? confirmDocumentPrivacy;

  /// Only reached on a seller's first farm. Additional farms skip this step
  /// because the server copies their ID and permit from the first farm, so
  /// there is nothing for the seller to do here.
  const FarmSetupVerifyScreen({
    super.key,
    required this.farmSetupData,
    this.readDocument = DocumentTextCheck.read,
    this.captureDocument,
    this.confirmDocumentPrivacy,
  });

  @override
  State<FarmSetupVerifyScreen> createState() => _FarmSetupVerifyScreenState();
}

class _FarmSetupVerifyScreenState extends State<FarmSetupVerifyScreen> {
  final _fullNameCtrl = TextEditingController();
  bool _checking = false;
  LegalCatalog? _legalCatalog;
  bool _documentPrivacyAccepted = false;

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

  XFile? get _idDocument => widget.farmSetupData.verificationDocument;

  XFile? get _certificateDocument => widget.farmSetupData.farmCertificate;

  String get _idSubtitle {
    final doc = _idDocument;
    if (doc == null) {
      return 'Take a clear photo of your government-issued ID';
    }
    return 'Photo captured: ${doc.name}';
  }

  String get _certificateSubtitle {
    final doc = _certificateDocument;
    if (doc == null) {
      return 'Take a clear photo of your farm permit or certificate';
    }
    return 'Photo captured: ${doc.name}';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.errorTerracotta,
      ),
    );
  }

  Future<void> _pickDocument({required bool isId}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      if (widget.confirmDocumentPrivacy != null) {
        if (!await widget.confirmDocumentPrivacy!() || !mounted) return;
      } else {
        final policies = _legalCatalog ?? await LegalService.catalog();
        if (!mounted) return;
        if (policies.published && !_documentPrivacyAccepted) {
          _showError(
            'Please read and agree to the ID & Permit Privacy Notice before taking a photo.',
          );
          return;
        }
        if (policies.published) {
          try {
            await LegalService.recordAccepted(policies, ['verification']);
          } catch (error) {
            if (mounted)
              _showError(error.toString().replaceFirst('Exception: ', ''));
            return;
          }
        }
        if (!mounted) return;
      }
      final picked = widget.captureDocument != null
          ? await widget.captureDocument!()
          : await Navigator.of(context).push<XFile>(
              MaterialPageRoute(builder: (_) => const DocumentCaptureScreen()),
            );
      if (picked == null || !mounted) return;
      final text = await widget.readDocument(picked);
      if (!mounted) return;
      if (!DocumentTextCheck.looksLikeDocument(text, isId: isId)) {
        _showError(
          isId
              ? 'Could not read a supported government ID. Retake with all text visible and no glare.'
              : 'Could not read a permit or certificate. Retake with the title and details visible.',
        );
        return;
      }
      if (isId && !DocumentTextCheck.matchesName(_fullNameCtrl.text, text)) {
        _showError(
          'The ID name must match your seller full name. Check your account name and retake a clear photo.',
        );
        return;
      }
      setState(() {
        if (isId) {
          widget.farmSetupData.verificationDocument = picked;
          widget.farmSetupData.verificationDocumentText = text;
        } else {
          widget.farmSetupData.farmCertificate = picked;
          widget.farmSetupData.farmCertificateText = text;
        }
      });
    } catch (_) {
      if (mounted) {
        _showError(
          'Unable to capture or read the document. Allow camera access and try again on an Android or iOS phone.',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _next() async {
    if (_checking) return;
    // Documents are always required here: this step is only reached on a
    // seller's first farm, where there is nothing to inherit them from.
    if (_idDocument == null || _certificateDocument == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please photograph both your valid ID and farm '
            'permit/certificate to continue.',
          ),
          backgroundColor: AppColors.errorTerracotta,
        ),
      );
      return;
    }
    if (widget.confirmDocumentPrivacy == null) {
      final policies = _legalCatalog ?? await LegalService.catalog();
      if (!mounted) return;
      if (policies.published && !_documentPrivacyAccepted) {
        _showError(
          'Please read and agree to the ID & Permit Privacy Notice before continuing.',
        );
        return;
      }
    }
    final data = widget.farmSetupData;
    if (!DocumentTextCheck.looksLikeDocument(
          data.verificationDocumentText,
          isId: true,
        ) ||
        !DocumentTextCheck.looksLikeDocument(
          data.farmCertificateText,
          isId: false,
        ) ||
        !DocumentTextCheck.matchesName(
          _fullNameCtrl.text,
          data.verificationDocumentText,
        )) {
      _showError(
        'Please retake your documents and make sure the ID matches your seller full name.',
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FarmSetupLocationScreen(farmSetupData: widget.farmSetupData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasId = _idDocument != null;
    final hasCert = _certificateDocument != null;
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
                  const Text(
                    'Please review the document privacy notice before taking photos.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  LegalRegistrationConsent(
                    documents: const ['verification'],
                    agreementLabel:
                        'I consent to ID and permit processing for seller verification.',
                    onChanged: (catalog, accepted) {
                      _legalCatalog = catalog;
                      _documentPrivacyAccepted = accepted;
                    },
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel(
                    'VALID ID',
                    badge: '(required)',
                    badgeColor: AppColors.primaryGreen,
                  ),
                  UploadBox(
                    icon: Icons.badge_outlined,
                    title: 'Government ID',
                    subtitle: _idSubtitle,
                    buttonLabel: hasId ? 'Retake photo' : 'Take photo',
                    isUploaded: hasId,
                    previewFile: _idDocument,
                    onTap: () => _pickDocument(isId: true),
                  ),
                  const SizedBox(height: 20),
                  const FieldLabel(
                    'FARM PERMIT / CERTIFICATE',
                    badge: '(required)',
                    badgeColor: AppColors.primaryGreen,
                  ),
                  UploadBox(
                    icon: Icons.description_outlined,
                    title: 'Farm Certificate/Permit',
                    subtitle: _certificateSubtitle,
                    buttonLabel: hasCert ? 'Retake photo' : 'Take photo',
                    isUploaded: hasCert,
                    previewFile: _certificateDocument,
                    onTap: () => _pickDocument(isId: false),
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
                  const SizedBox(height: 12),
                  const Text(
                    'Your seller full name must match your ID. An admin will review and approve your documents.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  if (_checking) const LinearProgressIndicator(),
                  const SizedBox(height: 28),
                  WizardNextButton(
                    label: _checking
                        ? 'Checking document...'
                        : 'Next: Pin Farm Location',
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
