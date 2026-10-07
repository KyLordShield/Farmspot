import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/farm_profile.dart';
import '../../services/farm_service.dart';
import '../../theme.dart';
import '../../widgets/lottie_loader.dart';
import '../../widgets/seller_widgets.dart';
import '../../widgets/farmspot_loader.dart';

/// Edit screen for the seller's own farm.
///
/// Deliberately edit-ONLY for name and description, plus photo management.
/// There is no location UI here of any kind (no barangay, no latitude/
/// longitude, no map): once a farm is approved its location is locked, so this
/// screen reinforces that by not exposing those fields at all.
///
/// Loads the farm via the public profile endpoint, pre-fills the form, and on
/// submit:
///   * deletes any photos the seller removed (DELETE per photo),
///   * marks the chosen photo as the cover when the seller tapped one
///     (PUT .../primary),
///   * calls FarmService.updateFarm(...) only when name/description changed, and
///   * calls FarmService.addFarmPhotos(...) separately when new photos were
///     picked (the JSON PATCH and the multipart upload are separate calls).
///
/// A non-dismissible brand Lottie loader covers the screen for the whole save
/// instead of a button spinner — photo uploads can take seconds, and a locked
/// "Saving changes..." layer reads as progress rather than a hang.
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
  final Set<String> _removedPhotoIds = {};

  /// The seller's explicit cover choice. Null until they tap a photo's star —
  /// null keeps whatever primary the server has.
  String? _coverChoice;

  /// The primary photo id the farm loaded with, so a submit that re-taps the
  /// existing cover is a no-op rather than a pointless round-trip.
  String? _savedCoverId;

  bool _isSubmitting = false;
  String? _submitError;

  /// Which photo reads as the cover right now: the explicit choice if the
  /// seller made one, else the farm's stored primary.
  String? get _currentCoverId => _coverChoice ?? _savedCoverId;

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
        _savedCoverId = _primaryPhotoId(farm);
        _coverChoice = null;
        _removedPhotoIds.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _friendly(e);
      });
    }
  }

  /// The id of the entry the backend marks as the farm's cover, if any.
  String? _primaryPhotoId(FarmProfileData farm) {
    for (final photo in farm.photos) {
      if (photo.isPrimary) return photo.id;
    }
    return null;
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

  /// Marks an existing photo as the cover. Also un-removes it, since a photo
  /// the seller just chose as the cover cannot also be on the delete list.
  void _makeCover(String photoId) {
    setState(() {
      _coverChoice = photoId;
      _removedPhotoIds.remove(photoId);
      _submitError = null;
    });
  }

  /// Toggles an existing photo between "will be removed" and "kept". Removing
  /// the chosen cover clears the choice — the server then auto-promotes the
  /// oldest remaining photo, which is the least surprising outcome.
  void _toggleRemove(String photoId) {
    setState(() {
      if (!_removedPhotoIds.add(photoId)) {
        _removedPhotoIds.remove(photoId);
      } else if (_coverChoice == photoId) {
        _coverChoice = null;
      }
      _submitError = null;
    });
  }

  bool get _nameChanged =>
      _farm != null && _nameCtrl.text.trim() != _farm!.name.trim();
  bool get _descriptionChanged => _farm != null &&
      _descriptionCtrl.text.trim() != _farm!.description.trim();

  /// Whether a submit would change the current cover. An explicit choice that
  /// still points at the loaded primary is a no-op.
  bool get _coverChanged =>
      _coverChoice != null && _coverChoice != _savedCoverId;

  Future<void> _submit() async {
    if (_isSubmitting || _farm == null) return;
    // At least one field must actually change for the save to mean anything.
    if (!_nameChanged &&
        !_descriptionChanged &&
        _newPhotos.isEmpty &&
        _removedPhotoIds.isEmpty &&
        !_coverChanged) {
      setState(() => _submitError = 'No changes to save.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    // Full-screen brand loader while the farm saves. Popped on either outcome
    // below. Shown before the first network call so a slow photo upload is a
    // locked "Saving changes..." layer, not a screen that looks hung.
    showFarmLottieLoading(context, message: 'Saving changes...');

    try {
      // Deletes go first so a removed cover leaves only the rest to promote,
      // and the explicit cover choice (below) lands last and wins.
      for (final photoId in _removedPhotoIds) {
        await FarmService.removeFarmPhoto(
          farmId: widget.farmId,
          photoId: photoId,
        );
      }

      if (_coverChanged) {
        await FarmService.setFarmPrimaryPhoto(
          farmId: widget.farmId,
          photoId: _coverChoice!,
        );
      }

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
      Navigator.of(context, rootNavigator: true).pop();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
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
      return const FarmSpotLoader();
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
    // Photos the farm already has, minus any the seller marked for removal.
    final keptPhotos =
        farm.photos.where((p) => !_removedPhotoIds.contains(p.id)).toList();
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
        // Photo management: existing photos can be removed or promoted to the
        // cover, and new ones are added alongside.
        const FieldLabel('FARM PHOTOS'),
        Text(
          'Tap a photo to set it as the cover. Use ✕ to remove a photo.',
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
              for (final photo in keptPhotos) ...[
                _EditableExistingPhoto(
                  key: ValueKey('farm_photo_edit_${photo.id}'),
                  url: photo.url,
                  isCover: photo.id == _currentCoverId,
                  onMakeCover: () => _makeCover(photo.id),
                  onRemove: () => _toggleRemove(photo.id),
                ),
                const SizedBox(width: 10),
              ],
              for (int i = 0; i < _newPhotos.length; i++) ...[
                _NewPhotoThumb(
                  file: _newPhotos[i],
                  onRemove: () => _removeNewPhoto(i),
                ),
                const SizedBox(width: 10),
              ],
              if (keptPhotos.isNotEmpty || _newPhotos.isNotEmpty)
                const SizedBox(width: 4),
              PhotoPlaceholder(isAddButton: true, onTap: _pickPhotos),
            ],
          ),
        ),
        if (_removedPhotoIds.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${_removedPhotoIds.length} existing photo(s) will be removed. '
            'Tap one below to restore it.',
            style: const TextStyle(color: Colors.black45, fontSize: 11),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final photo in farm.photos
                    .where((p) => _removedPhotoIds.contains(p.id)))
                  Padding(
                    key: ValueKey('farm_photo_removed_${photo.id}'),
                    padding: const EdgeInsets.only(right: 8),
                    child: _RemovedPhotoThumb(
                      url: photo.url,
                      onRestore: () => _toggleRemove(photo.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
      (_nameChanged ||
          _descriptionChanged ||
          _newPhotos.isNotEmpty ||
          _removedPhotoIds.isNotEmpty ||
          _coverChanged);

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

/// Interactive thumbnail of an EXISTING farm photo (from the stored Cloudinary
/// URL). The star promotes it to the cover (green ring + filled star when it
/// already is); ✕ marks it for removal.
class _EditableExistingPhoto extends StatelessWidget {
  final String url;
  final bool isCover;
  final VoidCallback onMakeCover;
  final VoidCallback onRemove;

  const _EditableExistingPhoto({
    super.key,
    required this.url,
    required this.isCover,
    required this.onMakeCover,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isCover ? null : onMakeCover,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCover ? AppColors.primaryGreen : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
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
              if (isCover)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryGreen,
                      borderRadius: BorderRadius.only(
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'COVER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close,
                        size: 16, color: Colors.white),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: isCover ? null : onMakeCover,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isCover
                          ? AppColors.primaryGreen
                          : Colors.black54,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                      ),
                    ),
                    child: Icon(
                      isCover ? Icons.star : Icons.star_border,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dimmed thumbnail of an existing photo the seller marked for removal.
/// Tapping it restores the photo (removing it from the delete list).
class _RemovedPhotoThumb extends StatelessWidget {
  final String url;
  final VoidCallback onRestore;

  const _RemovedPhotoThumb({required this.url, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRestore,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Opacity(
            opacity: 0.45,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image_outlined,
                        color: Colors.grey, size: 24),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(color: Colors.grey.shade300);
                  },
                ),
                const Center(
                  child: Icon(Icons.restore, color: Colors.white, size: 24),
                ),
              ],
            ),
          ),
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
                  return Image.memory(snapshot.data!, cacheWidth: 200, fit: BoxFit.cover);
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
