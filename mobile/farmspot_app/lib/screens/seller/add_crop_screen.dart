import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/crop_category.dart';
import '../../models/listing.dart';
import '../../services/farm_service.dart';
import '../../services/listing_service.dart';
import '../../theme.dart';
import '../../widgets/seller_widgets.dart';
import 'farm_live_screen.dart';

enum AvailabilityStatus {
  availableNow,
  soonToHarvest,
  notAvailable;

  /// Exact strings the backend expects for LST_STATUS.
  String get backendValue => switch (this) {
        AvailabilityStatus.availableNow => 'AVAILABLE_NOW',
        AvailabilityStatus.soonToHarvest => 'SOON_TO_HARVEST',
        AvailabilityStatus.notAvailable => 'NOT_AVAILABLE',
      };
}

class AddCropScreen extends StatefulWidget {
  /// True when this is the very first crop added right after farm setup —
  /// shows a simpler header and skips the "Which Farm?" picker, and finishes
  /// by navigating to the "Farm is Live" celebration screen instead of
  /// just popping back.
  final bool isFirstCrop;

  /// Required when [isFirstCrop] is true: the FRM_ID of the farm just created
  /// by the wizard. Ignored otherwise (the "Which Farm?" picker supplies it).
  final String? farmId;

  /// When provided, this screen edits that listing instead of creating one:
  /// the farm picker is hidden (a listing can't move farms), the form is
  /// pre-filled with the listing's current values, and submit calls
  /// updateListing() (+ updateListingPhoto() when a new photo was picked)
  /// instead of createListing(). Pops true after a successful edit.
  final Listing? existingListing;

  const AddCropScreen({
    super.key,
    this.isFirstCrop = false,
    this.farmId,
    this.existingListing,
  });

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen> {
  final _picker = ImagePicker();
  final _cropLabelCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _farmsLoading = true;
  List<Map<String, dynamic>> _farms = [];
  String? _selectedFarmId;

  bool _categoriesLoading = true;
  List<CropCategory> _categories = [];
  String? _categoriesError;
  int _selectedCategoryIndex = -1;

  /// Category-grid index the form started on (first category for a new crop,
  /// the listing's current category when editing). The back button compares
  /// against this to decide whether the user has unsaved changes.
  int _baselineCategoryIndex = -1;

  AvailabilityStatus _status = AvailabilityStatus.availableNow;
  DateTime? _harvestDate;

  /// Photos picked for the listing, in pick order, plus which one is marked as
  /// the primary (thumbnail) photo. The marked index is:
  ///  * create mode — 0 by default (the first photo), and tapping any picked
  ///    thumb re-marks it;
  ///  * edit mode — null until the farmer taps a *newly picked* photo, because
  ///    the listing's existing primary stays primary unless explicitly moved.
  /// Net: a new-upload always auto-promotes one to primary on the backend, so
  /// create-with-photos needs no explicit setPrimaryPhoto call for index 0.
  final List<XFile> _newPhotos = [];
  int? _markedNewIndex;

  /// Edit mode only: the generated photo id (LPHOTO_ID) currently starred as
  /// primary. Tapping an *existing* photo calls setPrimaryPhoto immediately
  /// (optimistic badge move, reverted on failure), while new photos are applied
  /// after their upload on save. Only one of [_editPrimaryId] / [_markedNewIndex]
  /// is non-null at a time.
  String? _editPrimaryId;
  bool _primaryBusy = false;

  bool _isSubmitting = false;
  String? _submitError;

  /// True when an existing listing is being edited rather than a new one
  /// created. Hides the farm picker and switches submit to the update path.
  bool get _isEditing => widget.existingListing != null;

  /// Edit mode: the listing's currently primary photo id, so the badge starts
  /// on the right thumbnail. The backend keeps `image` in sync with the
  /// primary photo, so falling back to the image URL match costs nothing.
  String? get _baselinePrimaryId {
    final existing = widget.existingListing;
    if (existing == null) return null;
    for (final photo in existing.photos) {
      if (photo.isPrimary) return photo.id;
    }
    final image = existing.image;
    if (image == null || image.isEmpty) return null;
    for (final photo in existing.photos) {
      if (photo.url == image) return photo.id;
    }
    return null;
  }

  /// Helper caption under the photo row describing how primary marking works
  /// for the current mode/picking state.
  String get _photoCaption {
    if (_newPhotos.isNotEmpty) {
      return 'Starred photo is the thumbnail buyers see. '
          '${_isEditing ? 'New photos upload on save.' : ''}';
    }
    if (_isEditing) {
      return 'Tap a photo to change the primary thumbnail. Tap + to add more.';
    }
    return 'Add one or more photos of your crop.';
  }

  AvailabilityStatus _statusFromBackend(String value) {
    switch (value) {
      case 'AVAILABLE_NOW':
        return AvailabilityStatus.availableNow;
      case 'SOON_TO_HARVEST':
        return AvailabilityStatus.soonToHarvest;
      default:
        return AvailabilityStatus.notAvailable;
    }
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existingListing;
    if (existing != null) {
      // Edit mode: no farm picker (a listing can't change farms), and the
      // form starts pre-filled from the listing's current values.
      _farmsLoading = false;
      _cropLabelCtrl.text = existing.cropIcon ?? '';
      _descCtrl.text = existing.description ?? '';
      _status = _statusFromBackend(existing.status);
      _harvestDate = DateTime.tryParse(existing.harvestDate ?? '');
      _editPrimaryId = _baselinePrimaryId;
    } else if (!widget.isFirstCrop) {
      _loadFarms();
    } else {
      _farmsLoading = false;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _cropLabelCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFarms() async {
    final farms = await FarmService.getFarms();
    if (!mounted) return;
    setState(() {
      _farmsLoading = false;
      _farms = farms;
      // Auto-select the first farm (getFarms() sorts APPROVED first, so this
      // is the operational farm under the one-farm rule) but keep every farm
      // visible/selectable in the UI.
      _selectedFarmId ??=
          farms.isNotEmpty ? farms.first['FRM_ID']?.toString() : null;
    });
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    try {
      final categories = await ListingService.fetchCropCategories();
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
        _categories = categories;
        _selectedCategoryIndex = _initialCategoryIndex(categories);
        _baselineCategoryIndex = _selectedCategoryIndex;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
        _categories = [];
        _categoriesError = _friendlyError(e);
      });
    }
  }

  /// Edit mode starts on the listing's current category; otherwise the first
  /// (only) item is selected like before. Falls back to 0 when the listing's
  /// category no longer exists.
  int _initialCategoryIndex(List<CropCategory> categories) {
    if (categories.isEmpty) return -1;
    final currentId = widget.existingListing?.categoryId;
    if (currentId == null || currentId.isEmpty) return 0;
    final index = categories.indexWhere((c) => c.id == currentId);
    return index == -1 ? 0 : index;
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
              subtitle: const Text('Pick one or more photos'),
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
    if (source == null || !mounted) return;

    if (source == ImageSource.camera) {
      final picked = await _picker.pickImage(source: source);
      if (picked != null && mounted) {
        setState(() {
          _newPhotos.add(picked);
          _markedNewIndex ??= 0;
          _submitError = null;
        });
      }
      return;
    }

    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _newPhotos.addAll(picked);
      _markedNewIndex ??= 0;
      _submitError = null;
    });
  }

  /// Removes a newly picked photo (not yet on the server) and fixes up the
  /// primary marker: removing a photo before the marked one shifts the index,
  /// and removing the marked photo itself falls back to the first remaining
  /// photo (create) or back to the existing primary (edit).
  void _removeNewPhoto(int index) {
    setState(() {
      _newPhotos.removeAt(index);
      final marked = _markedNewIndex;
      if (marked != null) {
        if (index < marked) {
          _markedNewIndex = marked - 1;
        } else if (index == marked) {
          _markedNewIndex = _newPhotos.isEmpty ? null : 0;
        }
      }
    });
  }

  /// Edit mode: tapping an existing thumbnail marks it primary *immediately*
  /// (the backend keeps `image` + home-feed thumbnails in sync). Optimistic
  /// badge move, reverted with a snackbar if the PATCH fails. Re-tapping the
  /// current primary is a no-op.
  Future<void> _setExistingPrimary(String photoId) async {
    final existing = widget.existingListing;
    if (existing == null || _primaryBusy || _editPrimaryId == photoId) return;

    final previous = _editPrimaryId;
    setState(() {
      _editPrimaryId = photoId;
      _markedNewIndex = null;
      _primaryBusy = true;
    });
    try {
      await ListingService.setPrimaryPhoto(
        listingId: existing.id,
        photoId: photoId,
      );
      if (!mounted) return;
      setState(() => _primaryBusy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _editPrimaryId = previous;
        _primaryBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update primary photo. ${_friendlyError(e)}'),
        ),
      );
    }
  }

  Future<void> _pickHarvestDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null && mounted) {
      setState(() => _harvestDate = picked);
    }
  }

  String get _farmIdForSubmit {
    if (widget.isFirstCrop) return widget.farmId ?? '';
    return _selectedFarmId ?? '';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    if (_isEditing) {
      await _submitEdit();
      return;
    }

    final farmId = _farmIdForSubmit;
    if (farmId.isEmpty) {
      setState(() => _submitError = widget.isFirstCrop
          ? 'Farm not found. Please complete the farm setup first.'
          : 'Please select a farm.');
      return;
    }
    if (_selectedCategoryIndex < 0 || _categories.isEmpty) {
      setState(() => _submitError = 'Please select a crop category.');
      return;
    }
    final category = _categories[_selectedCategoryIndex];

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final label = _cropLabelCtrl.text.trim();
      final desc = _descCtrl.text.trim();
      final created = await ListingService.createListing(
        farmId: farmId,
        categoryId: category.id,
        status: _status.backendValue,
        cropIcon: label.isEmpty ? null : label,
        harvestDate: _harvestDate,
        description: desc.isEmpty ? null : desc,
        photo: _newPhotos.isNotEmpty ? _newPhotos.first : null,
      );

      // Upload any extra picked photos, then — only when the farmer explicitly
      // marked a later photo as primary — promote it. The first photo is
      // already the primary after create/upload, so index 0 needs no call.
      // NOTE: photos uploaded inside a single batch can tie on the backend's
      // upload-time ordering (same second, random id tiebreak), so when several
      // are uploaded together the "marked" match is index-based and best-effort.
      if (_newPhotos.length > 1) {
        final updated = await ListingService.uploadListingPhotos(
          listingId: created.id,
          photos: _newPhotos.sublist(1),
        );
        final marked = _markedNewIndex;
        if (marked != null && marked > 0 && marked < updated.photos.length) {
          await ListingService.setPrimaryPhoto(
            listingId: created.id,
            photoId: updated.photos[marked].id,
          );
        }
      }

      if (!mounted) return;

      if (widget.isFirstCrop) {
        // Driven by the REAL created listing, not a locally guessed crop.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FarmLiveScreen(
              cropName: created.cropIcon ?? created.categoryName ?? 'Crop',
            ),
          ),
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = _friendlyError(e);
      });
    }
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  /// True when the form differs from how it started (edit mode compares
  /// against the listing) — the back button asks before discarding those.
  bool get _hasUnsavedChanges {
    final existing = widget.existingListing;
    if (existing != null) {
      final dateStr = _harvestDate != null ? _dateOnly(_harvestDate!) : null;
      final baseline = existing.harvestDate;
      final baselineDateStr = (baseline == null || baseline.length < 10)
          ? null
          : baseline.substring(0, 10);
      return _cropLabelCtrl.text.trim() != (existing.cropIcon ?? '') ||
          _status != _statusFromBackend(existing.status) ||
          dateStr != baselineDateStr ||
          _newPhotos.isNotEmpty ||
          _descCtrl.text.trim() != (existing.description ?? '') ||
          _selectedCategoryIndex != _baselineCategoryIndex;
    }
    return _cropLabelCtrl.text.trim().isNotEmpty ||
        _status != AvailabilityStatus.availableNow ||
        _harvestDate != null ||
        _newPhotos.isNotEmpty ||
        _descCtrl.text.trim().isNotEmpty ||
        _selectedCategoryIndex != _baselineCategoryIndex;
  }

  /// Top-left back: pops straight out when nothing was typed/changed, and
  /// asks for confirmation otherwise (Cancel / red "Discard", matching the
  /// app's logout and delete dialogs) so an accidental back can't silently
  /// drop real work.
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

  /// Edit-mode submit: calls updateListing() with the current form values and
  /// — only when a NEW photo was picked — updateListingPhoto() afterwards
  /// (the JSON PATCH and the multipart upload are separate backend calls).
  /// Pops true so MyFarmScreen can refresh its list.
  Future<void> _submitEdit() async {
    final existing = widget.existingListing!;
    if (_selectedCategoryIndex < 0 || _categories.isEmpty) {
      setState(() => _submitError = 'Please select a crop category.');
      return;
    }
    final category = _categories[_selectedCategoryIndex];
    final label = _cropLabelCtrl.text.trim();

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ListingService.updateListing(
        listingId: existing.id,
        categoryId: category.id,
        cropIcon: label.isEmpty ? null : label,
        harvestDate:
            _harvestDate != null ? _dateOnly(_harvestDate!) : null,
        status: _status.backendValue,
        description: _descCtrl.text,
      );

      // Existing-photo primary changes were already applied the moment the
      // farmer tapped them. Newly picked photos still need uploading, and a
      // newly marked one needs promotion (its LPHOTO_ID only exists after
      // upload, so this part has to wait for save).
      if (_newPhotos.isNotEmpty) {
        final afterUpload = await ListingService.uploadListingPhotos(
          listingId: existing.id,
          photos: _newPhotos,
        );
        final marked = _markedNewIndex;
        if (marked != null) {
          final existingCount = afterUpload.photos.length - _newPhotos.length;
          final targetIndex = existingCount + marked;
          if (targetIndex >= 0 && targetIndex < afterUpload.photos.length) {
            await ListingService.setPrimaryPhoto(
              listingId: existing.id,
              photoId: afterUpload.photos[targetIndex].id,
            );
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = _friendlyError(e);
      });
    }
  }

  static String _dateOnly(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Best-effort icon for a category. Known CAT_ICON names are mapped directly;
  /// otherwise the category name is scanned for a sensible default. Falls back
  /// to a generic leaf icon so the grid always renders.
  IconData _iconForCategory(CropCategory category) {
    final icon = (category.icon ?? '').trim().toLowerCase();
    final name = category.name.trim().toLowerCase();

    if (icon.isNotEmpty) {
      switch (icon) {
        case 'grass':
          return Icons.grass;
        case 'eco':
          return Icons.eco;
        case 'spa':
          return Icons.spa;
        case 'local_florist':
          return Icons.local_florist;
        case 'grain':
          return Icons.grain;
        case 'agriculture':
          return Icons.agriculture;
        case 'pets':
          return Icons.pets;
        case 'water_drop':
          return Icons.water_drop_outlined;
      }
    }

    if (name.contains('veget')) return Icons.spa;
    if (name.contains('fruit')) return Icons.local_florist;
    if (name.contains('grain') ||
        name.contains('rice') ||
        name.contains('cereal')) {
      return Icons.grain;
    }
    if (name.contains('livest') ||
        name.contains('poult') ||
        name.contains('animal')) {
      return Icons.pets;
    }
    if (name.contains('fish') || name.contains('aqua')) {
      return Icons.set_meal_outlined;
    }
    return Icons.eco;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            SetupHeader(
              title: _isEditing
                  ? 'Edit Crop'
                  : (widget.isFirstCrop ? 'Add First Crop' : 'Add Crop'),
              subtitle: _isEditing
                  ? 'Update crop details and availability'
                  : (widget.isFirstCrop
                      ? 'What are you selling this harvest?'
                      : 'Pick farm, crop, and availability'),
              onBack: _maybePop,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  if (!_isEditing && !widget.isFirstCrop) ...[
                    const FieldLabel('WHICH FARM?'),
                    if (_farmsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_farms.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No farms found. Complete the farm setup first.',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                      )
                    else
                      for (final farm in _farms)
                        SelectableOptionTile(
                          icon: Icons.location_on_outlined,
                          title: farm['FRM_NAME']?.toString() ?? 'Unnamed farm',
                          subtitle: farm['FRM_BARANGAY']?.toString() ?? '',
                          selected: _selectedFarmId == farm['FRM_ID'],
                          onTap: () => setState(
                              () => _selectedFarmId = farm['FRM_ID']?.toString()),
                        ),
                    const SizedBox(height: 8),
                  ],
                  const FieldLabel('CROP CATEGORY'),
                  if (_categoriesLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_categoriesError != null)
                    Text(
                      _categoriesError!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    )
                  else if (_categories.isEmpty)
                    const Text(
                      'No crop categories available yet.',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    )
                  else
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.1,
                      children: List.generate(_categories.length, (i) {
                        final category = _categories[i];
                        return CropPickerTile(
                          icon: _iconForCategory(category),
                          label: category.name,
                          selected: _selectedCategoryIndex == i,
                          onTap: () =>
                              setState(() => _selectedCategoryIndex = i),
                        );
                      }),
                    ),
                  const SizedBox(height: 18),
                  const FieldLabel(
                    'CROP NAME',
                    badge: '(optional)',
                    badgeColor: Colors.black38,
                  ),
                  TextField(
                    controller: _cropLabelCtrl,
                    decoration: _inputDecoration(
                      hint: 'e.g. Cabbage, Kangkong, Tomatoes',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel(
                    'DESCRIPTION',
                    badge: '(optional)',
                    badgeColor: Colors.black38,
                  ),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 4,
                    minLines: 2,
                    textInputAction: TextInputAction.newline,
                    decoration: _inputDecoration(
                      hint:
                          'e.g. Freshly harvested, farm-direct, passes quality checks',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('SET AVAILABILITY STATUS'),
                  SelectableOptionTile(
                    icon: Icons.check_circle_outline,
                    title: 'Available Now',
                    subtitle: 'Ready for buyers to contact you',
                    selected: _status == AvailabilityStatus.availableNow,
                    onTap: () =>
                        setState(() => _status = AvailabilityStatus.availableNow),
                  ),
                  SelectableOptionTile(
                    icon: Icons.schedule,
                    title: 'Soon to Harvest',
                    subtitle: "Let buyers know it's coming",
                    selected: _status == AvailabilityStatus.soonToHarvest,
                    onTap: () =>
                        setState(() => _status = AvailabilityStatus.soonToHarvest),
                  ),
                  SelectableOptionTile(
                    icon: Icons.bedtime_outlined,
                    title: 'Not Available',
                    subtitle: 'Hidden from marketplace',
                    selected: _status == AvailabilityStatus.notAvailable,
                    onTap: () =>
                        setState(() => _status = AvailabilityStatus.notAvailable),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel(
                    'HARVEST DATE',
                    badge: '(optional)',
                    badgeColor: Colors.black38,
                  ),
                  SelectableOptionTile(
                    icon: Icons.calendar_today_outlined,
                    title: _harvestDate != null
                        ? _formatDate(_harvestDate!)
                        : 'Pick a date',
                    subtitle: _harvestDate != null
                        ? 'Tap to change the date'
                        : 'When will the crop be ready?',
                    selected: _harvestDate != null,
                    onTap: _pickHarvestDate,
                  ),
                  if (_harvestDate != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _harvestDate = null),
                        child: const Text(
                          'Clear date',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  const FieldLabel(
                    'CROP PHOTO',
                    badge: '(optional)',
                    badgeColor: Colors.black38,
                  ),
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Edit mode shows the listing's existing gallery first,
                        // then any newly picked photos — matching how the
                        // backend orders photos (oldest first) so the "marked"
                        // index maths on save line up.
                        if (_isEditing)
                          for (final photo in widget.existingListing!.photos) ...[
                            _ExistingPhotoTile(
                              key: ObjectKey(photo.id),
                              url: photo.url,
                              primary: _editPrimaryId == photo.id,
                              busy: _primaryBusy && _editPrimaryId == photo.id,
                              onPrimaryTap: () =>
                                  _setExistingPrimary(photo.id),
                            ),
                            const SizedBox(width: 12),
                          ],
                        for (var i = 0; i < _newPhotos.length; i++) ...[
                          _NewPhotoTile(
                            key: ObjectKey(_newPhotos[i]),
                            file: _newPhotos[i],
                            primary: _markedNewIndex == i,
                            onPrimaryTap: () => setState(() {
                              _markedNewIndex = i;
                              _editPrimaryId = null;
                            }),
                            onRemove: () => _removeNewPhoto(i),
                          ),
                          const SizedBox(width: 12),
                        ],
                        PhotoPlaceholder(isAddButton: true, onTap: _pickPhotos),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _photoCaption,
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_submitError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _submitError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  WizardNextButton(
                    label: _isSubmitting
                        ? 'Saving...'
                        : (_isEditing ? 'Save Changes' : (
                            widget.isFirstCrop ? 'Add Crop & Go Live' : 'Add Crop')),
                    icon: Icons.check,
                    onPressed: _isSubmitting ? () {} : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
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

/// Thumbnail of an already-uploaded gallery photo (edit mode). Tapping it
/// marks it as the primary photo right away; a starred badge appears at the
/// top-left and an amber border highlights it. While the PATCH is in flight a
/// small spinner overlays the tapped tile and further taps are deferred.
class _ExistingPhotoTile extends StatelessWidget {
  final String url;
  final bool primary;
  final bool busy;
  final VoidCallback onPrimaryTap;

  const _ExistingPhotoTile({
    super.key,
    required this.url,
    required this.primary,
    required this.busy,
    required this.onPrimaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: primary || busy ? null : onPrimaryTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 96,
          height: 96,
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
              _photoBorder(primary: primary),
              if (primary)
                const Positioned(
                  top: 0,
                  left: 0,
                  child: _PrimaryBadge(),
                ),
              if (busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
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

/// Thumbnail of a freshly picked photo (not yet uploaded). Tapping it marks it
/// as the primary photo; the X removes it from the pending list. Renders the
/// picker's XFile as bytes (web-safe).
class _NewPhotoTile extends StatefulWidget {
  final XFile file;
  final bool primary;
  final VoidCallback onPrimaryTap;
  final VoidCallback onRemove;

  const _NewPhotoTile({
    super.key,
    required this.file,
    required this.primary,
    required this.onPrimaryTap,
    required this.onRemove,
  });

  @override
  State<_NewPhotoTile> createState() => _NewPhotoTileState();
}

class _NewPhotoTileState extends State<_NewPhotoTile> {
  late final Future<Uint8List> _bytes = widget.file.readAsBytes();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.primary ? null : widget.onPrimaryTap,
      child: ClipRRect(
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
              _photoBorder(primary: widget.primary),
              if (widget.primary)
                const Positioned(
                  top: 0,
                  left: 0,
                  child: _PrimaryBadge(),
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
      ),
    );
  }
}

/// Amber border + star badge on the photo currently marked as primary.
class _PrimaryBadge extends StatelessWidget {
  const _PrimaryBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFB300),
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: const Icon(Icons.star, size: 14, color: Colors.white),
    );
  }
}

Widget _photoBorder({required bool primary}) {
  return IgnorePointer(
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: primary ? const Color(0xFFFFB300) : Colors.transparent,
          width: 2,
        ),
      ),
    ),
  );
}