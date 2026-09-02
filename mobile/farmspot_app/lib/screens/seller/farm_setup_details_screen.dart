import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/farm_setup_data.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import 'farm_setup_verify_screen.dart';

class FarmSetupDetailsScreen extends StatefulWidget {
  final FarmSetupData farmSetupData;

  const FarmSetupDetailsScreen({super.key, required this.farmSetupData});

  @override
  State<FarmSetupDetailsScreen> createState() => _FarmSetupDetailsScreenState();
}

class _FarmSetupDetailsScreenState extends State<FarmSetupDetailsScreen> {
  static const int _maxPhotos = 4;

  final _picker = ImagePicker();
  late final TextEditingController _farmNameCtrl =
      TextEditingController(text: widget.farmSetupData.name);
  late final TextEditingController _descriptionCtrl =
      TextEditingController(text: widget.farmSetupData.description);
  late final TextEditingController _barangayCtrl =
      TextEditingController(text: widget.farmSetupData.barangay);
  String? _errorMessage;

  @override
  void dispose() {
    _farmNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _barangayCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
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

    final remaining = _maxPhotos - widget.farmSetupData.photos.length;
    final List<XFile> picked;
    if (source == ImageSource.gallery) {
      picked = await _picker.pickMultiImage(limit: remaining);
    } else {
      final single = await _picker.pickImage(source: ImageSource.camera);
      picked = single == null ? <XFile>[] : [single];
    }
    if (picked.isEmpty || !mounted) return;

    setState(() {
      widget.farmSetupData.photos.addAll(picked.take(remaining));
      _errorMessage = null;
    });
  }

  void _removePhoto(int index) {
    setState(() => widget.farmSetupData.photos.removeAt(index));
  }

  void _next() {
    widget.farmSetupData.name = _farmNameCtrl.text.trim();
    widget.farmSetupData.description = _descriptionCtrl.text.trim();
    widget.farmSetupData.barangay = _barangayCtrl.text.trim();

    if (!widget.farmSetupData.hasDetails || !widget.farmSetupData.hasPhotos) {
      setState(() => _errorMessage = _validationMessage());
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FarmSetupVerifyScreen(farmSetupData: widget.farmSetupData),
      ),
    );
  }

  String _validationMessage() {
    if (_farmNameCtrl.text.trim().isEmpty) {
      return 'Please enter your farm name.';
    }
    if (_descriptionCtrl.text.trim().isEmpty) {
      return 'Please add a short description of your farm.';
    }
    if (_barangayCtrl.text.trim().isEmpty) {
      return 'Please enter your barangay.';
    }
    return 'Please add at least one farm photo.';
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.farmSetupData.photos;
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
                        for (int i = 0; i < photos.length; i++) ...[
                          _PhotoThumb(
                            file: photos[i],
                            onRemove: () => _removePhoto(i),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (photos.length < _maxPhotos)
                          PhotoPlaceholder(isAddButton: true, onTap: _pickPhotos),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_errorMessage != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 16),
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

class _PhotoThumb extends StatefulWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _PhotoThumb({required this.file, required this.onRemove});

  @override
  State<_PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<_PhotoThumb> {
  late final Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List>(
              future: _bytes,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                }
                if (snapshot.hasError) {
                  return Container(
                    color: Colors.grey.shade200,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                      size: 20,
                    ),
                  );
                }
                return Container(
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: widget.onRemove,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}