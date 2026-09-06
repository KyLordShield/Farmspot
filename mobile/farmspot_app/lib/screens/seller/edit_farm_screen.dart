import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/farm_profile.dart';
import '../../services/farm_service.dart';
import '../../theme.dart';
import '../../widgets/seller_widgets.dart';

/// Edit screen for the seller's own farm.
///
/// Deliberately edit-ONLY for name and description, plus APPEND-ONLY photo
/// uploads. There is no location UI here of any kind (no barangay, no
/// latitude/longitude, no map): once a farm is approved its location is
/// locked, so this screen reinforces that by not exposing those fields at all.
///
/// Loads the farm via the public profile endpoint, pre-fills the form, and on
/// submit:
///   * calls FarmService.updateFarm(...) only when name/description changed, and
///   * calls FarmService.addFarmPhotos(...) separately when new photos were
///     picked (the JSON PATCH and the multipart upload are separate calls).
class EditFarmScreen extends StatefulWidget {
  final String farmId;

  const EditFarmScreen({super.key, required this.farmId});

  @override
  State<EditFarmScreen> createState() => _EditFarmScreenState();
}

class _EditFarmScreenState extends State<EditFarmScreen> {
  final _picker = ImagePicker();

  bool _loading = true;
  FarmProfileData? _farm;
  String? _loadError;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;

  final List<XFile> _newPhotos = [];
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    // Controllers start empty and are filled once the farm loads.
    _nameCtrl = TextEditingController();
    _descriptionCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final farm = await FarmService.fetchFarmProfile(widget.farmId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _farm = farm;
        _nameCtrl.text = farm.name;
        _descriptionCtrl.text = farm.description;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _friendly(e);
      });
    }
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

    final List<XFile> picked;
    if (source == ImageSource.gallery) {
      picked = await _picker.pickMultiImage();
    } else {
      final single = await _picker.pickImage(source: ImageSource.camera);
      picked = single == null ? <XFile>[] : [single];
    }
    if (picked.isEmpty || !mounted) return;

    setState(() {
      _newPhotos.addAll(picked);
      _submitError = null;
    });
  }

  void _removeNewPhoto(int index) {
    setState(() => _newPhotos.removeAt(index));
  }

  bool get _nameChanged =>
      _farm != null && _nameCtrl.text.trim() != _farm!.name.trim();
  bool get _descriptionChanged => _farm != null &&
      _descriptionCtrl.text.trim() != _farm!.description.trim();

  Future<void> _submit() async {
    if (_isSubmitting || _farm == null) return;
    // At least one field must actually change for the save to mean anything.
    if (!_nameChanged && !_descriptionChanged && _newPhotos.isEmpty) {
      setState(() => _submitError = 'No changes to save.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      if (_nameChanged || _descriptionChanged) {
        await FarmService.updateFarm(
          farmId: widget.farmId,
          name: _nameChanged ? _nameCtrl.text.trim() : null,
          description: _descriptionChanged ? _descriptionCtrl.text.trim() : null,
        );
      }

      if (_newPhotos.isNotEmpty) {
        await FarmService.addFarmPhotos(
          farmId: widget.farmId,
          photos: List.of(_newPhotos),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = _friendly(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            SetupHeader(
              title: 'Edit Farm',
              subtitle: 'Update farm details and photos',
              onBack: _maybePop,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final farm = _farm!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        const FieldLabel('FARM NAME'),
        TextField(
          controller: _nameCtrl,
          maxLength: 150,
          decoration: _inputDecoration(),
        ),
        const SizedBox(height: 8),
        const FieldLabel('DESCRIPTION'),
        TextField(
          controller: _descriptionCtrl,
          minLines: 3,
          maxLines: 5,
          decoration: _inputDecoration(),
        ),
        const SizedBox(height: 18),
        // Append-only photo section: existing photos are read-only (no
        // delete/replace UI at this stage) and new ones are added alongside.
        const FieldLabel('FARM PHOTOS'),
        Text(
          'Existing photos stay untouched.', 
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final url in farm.photos) ...[
                _ExistingPhoto(url: url),
                const SizedBox(width: 10),
              ],
              for (int i = 0; i < _newPhotos.length; i++) ...[
                _NewPhotoThumb(
                  file: _newPhotos[i],
                  onRemove: () => _removeNewPhoto(i),
                ),
                const SizedBox(width: 10),
              ],
              if (farm.photos.isNotEmpty || _newPhotos.isNotEmpty)
                const SizedBox(width: 4),
              PhotoPlaceholder(isAddButton: true, onTap: _pickPhotos),
            ],
          ),
        ),
        if (_newPhotos.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${_newPhotos.length} new photo(s) will be added.',
            style: const TextStyle(color: Colors.black45, fontSize: 11),
          ),
        ],
        const SizedBox(height: 18),
        if (_submitError != null) ...[
          Text(
            _submitError!,
            style: const TextStyle(color: Colors.red, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
        WizardNextButton(
          label: _isSubmitting ? 'Saving...' : 'Save Changes',
          icon: Icons.check,
          onPressed: _isSubmitting ? () {} : _submit,
        ),
      ],
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

  static String _friendly(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  /// True when the form differs from how it started — the back button asks
  /// before discarding those.
  bool get _hasUnsavedChanges =>
      _farm != null &&
      (_nameChanged || _descriptionChanged || _newPhotos.isNotEmpty);

  /// Top-left back: pops straight out when nothing changed, and asks for
  /// confirmation otherwise (Cancel / red "Discard", matching the app's
  /// logout and delete dialogs) so an accidental back can't silently drop
  /// real work.
  Future<void> _maybePop() async {
    if (_isSubmitting) return;
    if (!_hasUnsavedChanges) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Read-only thumbnail of an EXISTING farm photo (from the stored Cloudinary
/// URL). No remove affordance — photos are append-only at this stage.
class _ExistingPhoto extends StatelessWidget {
  final String url;

  const _ExistingPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        height: 96,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined,
                color: Colors.grey, size: 24),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A newly-picked (not yet uploaded) photo, removable before saving.
class _NewPhotoThumb extends StatefulWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _NewPhotoThumb({required this.file, required this.onRemove});

  @override
  State<_NewPhotoThumb> createState() => _NewPhotoThumbState();
}

class _NewPhotoThumbState extends State<_NewPhotoThumb> {
  late final Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        height: 96,
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
                      size: 24,
                    ),
                  );
                }
                return Container(
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
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
                  padding: const EdgeInsets.all(4),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
