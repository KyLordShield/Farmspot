import 'package:farmspot_app/widgets/photo_moderation_gate.dart';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:farmspot_app/utils/input_limits.dart';
import 'package:farmspot_app/utils/photo_limits.dart';
import 'package:cross_file/cross_file.dart';
import 'package:lottie/lottie.dart';

import '../../models/crop_category.dart';
import '../../models/crop_shelf_life.dart';
import '../../models/listing.dart';
import '../../services/farm_service.dart';
import '../../services/image_detect_service.dart';
import '../../services/listing_service.dart';
import '../../theme.dart';
import '../../widgets/crop_photo_preview.dart';
import '../../widgets/seller_widgets.dart';
import '../../widgets/farmspot_loader.dart';
import '../../widgets/lottie_loader.dart';
import '../image_search_screen.dart';
import 'farm_live_screen.dart';

Future<List<XFile>> _screenCropPhotos(
  BuildContext context,
  List<XFile> photos,
) =>
    screenPhotos(context, photos, showDebugResults: false, showProgress: false);

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
  final Future<List<XFile>> Function(BuildContext, List<XFile>) moderatePhotos;

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
  final Future<List<XFile>> Function(int remaining)? selectPhotos;
  final Future<List<CropCategory>> Function() loadCategories;
  final Future<List<DetectedCrop>> Function(XFile) detectCrops;
  final bool openCameraOnStart;

  const AddCropScreen({
    super.key,
    this.moderatePhotos = _screenCropPhotos,
    this.isFirstCrop = false,
    this.farmId,
    this.existingListing,
    this.selectPhotos,
    this.loadCategories = ListingService.fetchCropCategories,
    this.detectCrops = ImageDetectService.detectListingCrops,
    this.openCameraOnStart = false,
  });

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen> {
  final _cropLabelCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  static const _cropDetails = {
    'kamatis': (
      'Tomato',
      'Tomatoes for fresh salads, homemade sauces, and everyday cooking.',
    ),
    'lettuce': (
      'Lettuce',
      'Lettuce for crisp salads, sandwich layers, and wraps.',
    ),
    'cucumber': (
      'Cucumber',
      'Cucumbers for crisp salads, quick snacks, and pickling.',
    ),
    'chili': (
      'Chili',
      'Chili peppers for adding heat to sauces, marinades, and stir-fries.',
    ),
    'green_bean': (
      'Green Beans',
      'Green beans for stir-fries, soups, and vegetable sides.',
    ),
    'cabbage': ('Cabbage', 'Cabbage for crunchy slaws, soups, and stir-fries.'),
    'chayote': (
      'Chayote',
      'Mild-flavored chayote for tinola and sautéed dishes.',
    ),
    'bok_choy': (
      'Bok Choy',
      'Bok choy for stir-fries, noodle dishes, and soups.',
    ),
    'carrot': (
      'Carrot',
      'Carrots for crunchy snacks, salads, soups, and stews.',
    ),
  };

  bool _scanningCrop = false;
  bool _openingCamera = false;
  bool _checkingPhoto = false;
  bool _matchingPhotos = false;
  bool _choosingCrop = false;
  XFile? _detectedPhoto;
  DetectedCrop? _selectedDetection;
  DetectedCrop? _confirmedUpcomingDetection;
  String? _scanMessage;
  String? _suggestedDescription;
  bool _categoryChosenManually = false;

  bool get _canScanCrop =>
      !_isEditing && !_scanningCrop && _detectedPhoto == null;

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
  bool _harvestDateSuggested = false;
  static const _maxHarvestLeadDays = 60;

  static const _harvestLeadDays = {
    'kamatis': 14,
    'lettuce': 7,
    'cucumber': 7,
    'chili': 14,
    'green_bean': 7,
    'cabbage': 14,
    'chayote': 14,
    'bok_choy': 7,
    'carrot': 14,
  };

  int get _harvestLead {
    final name = _cropLabelCtrl.text.trim().toLowerCase();
    if (_harvestLeadDays.containsKey(name)) return _harvestLeadDays[name]!;
    for (final entry in _cropDetails.entries) {
      final label = entry.value.$1.toLowerCase();
      if (name == label || name == '${label}s') {
        return _harvestLeadDays[entry.key]!;
      }
    }
    return 7;
  }

  String get _availableNowSubtitle {
    const ready = 'Ready for buyers to contact you';
    if (_status != AvailabilityStatus.availableNow) return ready;
    if (_isEditing) {
      return shelfLifeRemaining(
            _status.backendValue,
            DateTime.tryParse(widget.existingListing?.expiryDate ?? ''),
          ) ??
          ready;
    }

    final days = _selectedDetection?.shelfLifeDays;
    if (days != null) return 'Estimated shelf life · About $days days';

    final estimate = cropShelfLife(_cropLabelCtrl.text);
    return estimate == null ? ready : 'Standard listing window · $estimate';
  }

  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  DateTime get _lastHarvestDate =>
      DateUtils.addDaysToDate(_today, _maxHarvestLeadDays);

  void _suggestHarvestDate() {
    _harvestDate = DateUtils.addDaysToDate(_today, _harvestLead);
    _harvestDateSuggested = true;
  }

  void _setAvailableNow() {
    setState(() {
      _status = AvailabilityStatus.availableNow;
      _harvestDate = null;
      _confirmedUpcomingDetection = null;
    });
  }

  Future<bool> _confirmUpcomingCrop() async {
    final detection = _selectedDetection;
    if (detection == null ||
        !detection.looksRipe ||
        identical(detection, _confirmedUpcomingDetection)) {
      return true;
    }

    final status = await showDialog<AvailabilityStatus>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This photo looks ripe'),
        content: const Text('Is the batch ready for buyers?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, AvailabilityStatus.availableNow),
            child: const Text('Available now'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, AvailabilityStatus.soonToHarvest),
            child: const Text('Keep harvest date'),
          ),
        ],
      ),
    );
    if (!mounted || !identical(detection, _selectedDetection)) return false;
    if (status == AvailabilityStatus.availableNow) _setAvailableNow();
    if (status != AvailabilityStatus.soonToHarvest) return false;
    _confirmedUpcomingDetection = detection;
    return true;
  }

  Future<void> _selectSoonToHarvest() async {
    if (!await _confirmUpcomingCrop() || !mounted) return;
    setState(() {
      _status = AvailabilityStatus.soonToHarvest;
      if (_harvestDate == null) _suggestHarvestDate();
    });
  }

  String? get _harvestDateError {
    if (_status != AvailabilityStatus.soonToHarvest) return null;
    final date = _harvestDate;
    if (date == null) return 'Please pick an expected harvest date.';
    if (DateUtils.dateOnly(date).isBefore(_today) ||
        DateUtils.dateOnly(date).isAfter(_lastHarvestDate)) {
      return 'Choose a harvest date within the next $_maxHarvestLeadDays days.';
    }
    return null;
  }

  /// Newly picked photos. A new listing uses its scanned photo as primary.
  /// An existing listing keeps its primary unless the farmer changes it.
  final List<XFile> _newPhotos = [];
  final Set<String> _removedPhotoIds = {};
  int get _photoCount =>
      (widget.existingListing?.photos.length ?? 0) -
      _removedPhotoIds.length +
      _newPhotos.length;

  Future<void> _addPickedPhotos(List<XFile> picked, int remaining) async {
    if (!mounted || picked.isEmpty || remaining <= 0) return;
    setState(() {
      _checkingPhoto = true;
      _scanMessage = null;
    });
    const uploadLimit = 5 * 1024 * 1024;
    final sizedPhotos = <XFile>[];
    for (final photo in picked.take(remaining)) {
      try {
        if (await photo.length() <= uploadLimit) sizedPhotos.add(photo);
      } catch (_) {
        // Unreadable images cannot be uploaded.
      }
    }
    if (!mounted) return;
    if (sizedPhotos.isEmpty) {
      setState(() {
        _checkingPhoto = false;
        _scanMessage = 'Choose a readable photo under 5 MB.';
      });
      return;
    }
    List<XFile> accepted;
    try {
      accepted = await widget.moderatePhotos(context, sizedPhotos);
    } catch (_) {
      accepted = [];
    }
    if (!mounted) return;
    setState(() => _checkingPhoto = false);

    if (accepted.isEmpty) {
      setState(
        () => _scanMessage = 'That photo could not be used. Try another photo.',
      );
      return;
    }

    if (_canScanCrop) {
      final primary = accepted.first;
      setState(() {
        _newPhotos.add(primary);
        _markedNewIndex = 0;
      });
      await _scanCrop(primary);
      if (!mounted) return;
      if (_detectedPhoto != primary) {
        setState(() {
          _newPhotos.remove(primary);
          _markedNewIndex = null;
        });
        return;
      }
      accepted = accepted.skip(1).toList();
    }
    if (accepted.isEmpty) return;

    final crop =
        _selectedDetection?.name ??
        _cropKeyForName(widget.existingListing?.cropIcon);
    if (crop == null) {
      setState(
        () => _scanMessage = 'The scanner cannot verify photos for this crop.',
      );
      return;
    }

    setState(() => _matchingPhotos = true);
    final matching = <XFile>[];
    String? message;
    for (final photo in accepted) {
      try {
        final names = (await widget.detectCrops(
          photo,
        )).map((item) => item.name).toSet();
        if (!mounted) return;
        if (names.length == 1 && names.contains(crop)) {
          matching.add(photo);
        } else {
          message =
              'Use a photo that clearly shows only ${_cropDetails[crop]!.$1}.';
        }
      } catch (_) {
        if (!mounted) return;
        message = 'Could not verify a photo. Try again.';
      }
    }
    setState(() {
      _matchingPhotos = false;
      _newPhotos.addAll(matching);
      _scanMessage = message;
    });
  }

  String? _cropKeyForName(String? name) {
    final normalized = name?.trim().toLowerCase();
    for (final entry in _cropDetails.entries) {
      final label = entry.value.$1.toLowerCase();
      if (normalized == entry.key ||
          normalized == label ||
          normalized == '${label}s') {
        return entry.key;
      }
    }
    return switch (normalized) {
      'tomatoes' => 'kamatis',
      'chillies' || 'chilies' || 'sili' || 'chilli' => 'chili',
      'pechay' => 'bok_choy',
      'sayote' => 'chayote',
      'repolyo' => 'cabbage',
      'pipino' => 'cucumber',
      'green bean' || 'baguio beans' => 'green_bean',
      _ => null,
    };
  }

  Future<void> _scanCrop(XFile photo) async {
    if (!_canScanCrop || !_newPhotos.contains(photo)) return;
    final originalDescription = _descCtrl.text;
    setState(() {
      _scanningCrop = true;
      _scanMessage = null;
      _submitError = null;
    });

    String? message;
    try {
      final detections = await widget.detectCrops(photo);
      if (!mounted || !_newPhotos.contains(photo)) return;
      final options = {
        for (final detection in detections)
          if (_cropDetails.containsKey(detection.name)) detection.name,
      }.toList();
      if (options.isEmpty) {
        message = 'No supported crop detected.';
        return;
      }
      if (options.length > 1) setState(() => _choosingCrop = true);
      final crop = options.length == 1
          ? options.single
          : await _chooseCrop(options);
      if (!mounted || !_newPhotos.contains(photo)) return;
      if (crop == null) {
        message = 'No crop selected.';
        return;
      }
      final (name, description) = _cropDetails[crop]!;
      _detectedPhoto = photo;
      _selectedDetection = detections.firstWhere((item) => item.name == crop);
      _markedNewIndex = _newPhotos.indexOf(photo);
      _cropLabelCtrl.text = name;
      if (_status == AvailabilityStatus.soonToHarvest &&
          _harvestDateSuggested) {
        _suggestHarvestDate();
      }
      if (!_categoryChosenManually) _suggestCategory(name);
      if (originalDescription.trim().isEmpty &&
          _descCtrl.text == originalDescription) {
        _descCtrl.text = description;
        _suggestedDescription = description;
      }
    } on ImageDetectException catch (error) {
      message = error.message;
    } catch (_) {
      message = 'Could not scan this photo.';
    } finally {
      if (mounted) {
        setState(() {
          _scanningCrop = false;
          _choosingCrop = false;
          _scanMessage = message;
        });
      }
    }
  }

  Future<String?> _chooseCrop(List<String> options) {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which crop are you listing?'),
        children: [
          for (final crop in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, crop),
              child: Text(_cropDetails[crop]!.$1),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('None of these'),
          ),
        ],
      ),
    );
  }

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
      // A date only belongs to a soon-to-harvest crop. An available-now or
      // not-available listing must not carry the date over, otherwise saving
      // would keep re-attaching it.
      _harvestDate = _status == AvailabilityStatus.soonToHarvest
          ? DateTime.tryParse(existing.harvestDate ?? '')
          : null;
      _editPrimaryId = _baselinePrimaryId;
    } else if (!widget.isFirstCrop) {
      _loadFarms();
    } else {
      _farmsLoading = false;
    }
    _loadCategories();
    if (!_isEditing && widget.openCameraOnStart) {
      _openingCamera = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _captureCropPhoto(PhotoLimits.listing);
      });
    }
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
      _selectedFarmId ??= farms.isNotEmpty
          ? farms.first['FRM_ID']?.toString()
          : null;
    });
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    try {
      final categories = await widget.loadCategories();
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
        _categories = categories;
        _selectedCategoryIndex = _initialCategoryIndex(categories);
        _baselineCategoryIndex = _selectedCategoryIndex;
      });
      if (!_isEditing && _cropLabelCtrl.text.trim().isNotEmpty) {
        _suggestCategory(_cropLabelCtrl.text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
        _categories = [];
        _categoriesError = _friendlyError(e);
      });
    }
  }

  void _suggestCategory(String crop) {
    if (_categories.isEmpty) return;
    final match = CropCategory.suggestIndex(_categories, crop);
    final other = _categories.indexWhere((c) => c.id == 'OTHERS');
    setState(() {
      _selectedCategoryIndex = match >= 0 ? match : other;
    });
  }

  /// Edit mode starts on the listing's current category; otherwise the first
  /// (only) item is selected like before. Falls back to 0 when the listing's
  /// category no longer exists.
  int _initialCategoryIndex(List<CropCategory> categories) {
    if (categories.isEmpty) return -1;
    final currentId = widget.existingListing?.categoryId;
    if (currentId == null || currentId.isEmpty) {
      final match = CropCategory.suggestIndex(categories, _cropLabelCtrl.text);
      return match >= 0 ? match : -1;
    }
    final index = categories.indexWhere((c) => c.id == currentId);
    if (index >= 0) return index;
    final suggested = CropCategory.suggestIndex(
      categories,
      _cropLabelCtrl.text,
    );
    return suggested >= 0
        ? suggested
        : categories.indexWhere((c) => c.id == 'OTHERS');
  }

  Future<void> _captureCropPhoto(int remaining) async {
    try {
      do {
        setState(() => _openingCamera = true);
        final selectPhotos = widget.selectPhotos;
        final photo = selectPhotos != null
            ? (await selectPhotos(1)).firstOrNull
            : await Navigator.of(context).push<XFile>(
                MaterialPageRoute(
                  builder: (_) => ImageSearchScreen(
                    selectPhoto: true,
                    captureFeedback: _scanMessage,
                  ),
                ),
              );
        if (!mounted) return;
        if (photo == null) {
          if (widget.openCameraOnStart && _canScanCrop) await _maybePop();
          return;
        }
        setState(() => _openingCamera = false);
        await _addPickedPhotos([photo], remaining);
        if (mounted && widget.openCameraOnStart && _canScanCrop) {
          final index = _newPhotos.indexOf(photo);
          if (index >= 0) _removeNewPhoto(index);
        }
      } while (mounted && widget.openCameraOnStart && _canScanCrop);
    } finally {
      if (mounted && _openingCamera) setState(() => _openingCamera = false);
    }
  }

  Future<void> _pickPhotos() async {
    final remaining = PhotoLimits.listing - _photoCount;
    if (remaining <= 0) {
      setState(
        () => _submitError =
            'Maximum 5 photos per listing. Remove a photo before adding more.',
      );
      return;
    }
    if (widget.openCameraOnStart && _canScanCrop) {
      await _captureCropPhoto(remaining);
      return;
    }
    if (widget.selectPhotos != null) {
      await _addPickedPhotos(await widget.selectPhotos!(remaining), remaining);
      return;
    }
    await _captureCropPhoto(remaining);
  }

  /// Removes a newly picked photo (not yet on the server) and fixes up the
  /// primary marker: removing a photo before the marked one shifts the index,
  /// and removing the marked photo itself falls back to the first remaining
  /// photo (create) or back to the existing primary (edit).
  void _removeNewPhoto(int index) {
    setState(() {
      final removed = _newPhotos.removeAt(index);
      if (removed == _detectedPhoto) {
        // All extra shots were verified against the removed primary.
        _newPhotos.clear();
        _detectedPhoto = null;
        _selectedDetection = null;
        _confirmedUpcomingDetection = null;
        _scanMessage = null;
        _cropLabelCtrl.clear();
        if (_descCtrl.text == _suggestedDescription) _descCtrl.clear();
        _suggestedDescription = null;
        _selectedCategoryIndex = -1;
        _categoryChosenManually = false;
      }
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
    final today = _today;
    final lastDate = _lastHarvestDate;
    final saved = DateUtils.dateOnly(_harvestDate ?? today);
    final initial = saved.isBefore(today)
        ? today
        : saved.isAfter(lastDate)
        ? lastDate
        : saved;
    final picked = await showDatePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDate: initial,
      firstDate: today,
      lastDate: lastDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _harvestDate = picked;
        _harvestDateSuggested = false;
      });
    }
  }

  String get _farmIdForSubmit {
    if (widget.isFirstCrop) return widget.farmId ?? '';
    return _selectedFarmId ?? '';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (_newPhotos.isNotEmpty && _photoCount > PhotoLimits.listing) {
      setState(() => _submitError = 'Maximum 5 photos per listing.');
      return;
    }

    if (_isEditing) {
      await _submitEdit();
      return;
    }

    if (_status == AvailabilityStatus.soonToHarvest) {
      if (!await _confirmUpcomingCrop() || !mounted || _isSubmitting) return;
    }

    final detectedPhoto = _detectedPhoto;
    if (detectedPhoto == null ||
        !_newPhotos.contains(detectedPhoto) ||
        _cropLabelCtrl.text.trim().isEmpty) {
      setState(
        () => _submitError =
            'Scan a photo with a supported crop before publishing.',
      );
      return;
    }
    final farmId = _farmIdForSubmit;
    if (farmId.isEmpty) {
      setState(
        () => _submitError = widget.isFirstCrop
            ? 'Farm not found. Please complete the farm setup first.'
            : 'Please select a farm.',
      );
      return;
    }
    if (_selectedCategoryIndex < 0 || _categories.isEmpty) {
      setState(() => _submitError = 'Please select a crop category.');
      return;
    }
    final harvestError = _harvestDateError;
    if (harvestError != null) {
      setState(() => _submitError = harvestError);
      return;
    }
    final category = _categories[_selectedCategoryIndex];

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    showFarmLottieLoading(context, message: 'Saving your crop...');

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
        photo: detectedPhoto,
        estimateToken: _status == AvailabilityStatus.availableNow
            ? _selectedDetection?.estimateToken
            : null,
      );

      final additionalPhotos = _newPhotos
          .where((photo) => photo != detectedPhoto)
          .toList();
      if (additionalPhotos.isNotEmpty) {
        await ListingService.uploadListingPhotos(
          listingId: created.id,
          photos: additionalPhotos,
        );
      }

      if (!mounted) return;

      // Close the lottie overlay before switching screens.
      Navigator.of(context, rootNavigator: true).pop();

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
      Navigator.of(context, rootNavigator: true).pop();
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
      final baselineStatus = _statusFromBackend(existing.status);
      final dateStr = _harvestDate != null ? _dateOnly(_harvestDate!) : null;
      final baseline = existing.harvestDate;
      // The stored date only counts as a baseline while the listing was soon
      // to harvest; for any other status it is treated as absent, so opening
      // such a listing is not falsely reported as already having changes.
      final baselineDateStr =
          baselineStatus == AvailabilityStatus.soonToHarvest &&
              baseline != null &&
              baseline.length >= 10
          ? baseline.substring(0, 10)
          : null;
      return _cropLabelCtrl.text.trim() != (existing.cropIcon ?? '') ||
          _status != baselineStatus ||
          dateStr != baselineDateStr ||
          _newPhotos.isNotEmpty ||
          _removedPhotoIds.isNotEmpty ||
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
    final soon = _status == AvailabilityStatus.soonToHarvest;
    final harvestError = _harvestDateError;
    if (harvestError != null) {
      setState(() => _submitError = harvestError);
      return;
    }
    final category = _categories[_selectedCategoryIndex];

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    showFarmLottieLoading(context, message: 'Saving your crop...');

    try {
      for (final photoId in _removedPhotoIds) {
        await ListingService.deleteListingPhoto(
          listingId: existing.id,
          photoId: photoId,
        );
      }
      await ListingService.updateListing(
        listingId: existing.id,
        categoryId: category.id,
        // Only a soon-to-harvest crop carries a date; any other status sends
        // an empty value so the server clears whatever date was stored.
        harvestDate: soon ? _dateOnly(_harvestDate!) : '',
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
      Navigator.of(context, rootNavigator: true).pop();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
    if (_openingCamera || _checkingPhoto || _scanningCrop || _matchingPhotos) {
      final (title, detail) = _openingCamera
          ? ('Opening camera', 'Get the crop in the frame.')
          : _checkingPhoto
          ? (
              'Checking your photo',
              'Making sure it can be used in the listing.',
            )
          : _matchingPhotos
          ? (
              'Checking the crop match',
              'Making sure the new photo shows the same crop as your listing.',
            )
          : _choosingCrop
          ? ('Multiple crops found', 'Choose the crop you want to list.')
          : (
              'Identifying your crop',
              'Looking for the crop in your photo. This can take a moment.',
            );
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Add Crop'),
          leading: BackButton(onPressed: _maybePop),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_choosingCrop)
                    Lottie.asset(
                      'assets/animations/Image scan.lottie',
                      width: 200,
                      height: 200,
                      errorBuilder: (_, _, _) => const FarmSpotLoader(size: 56),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(detail, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      );
    }
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
                        child: Center(child: FarmSpotLoader(size: 32)),
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
                            () => _selectedFarmId = farm['FRM_ID']?.toString(),
                          ),
                        ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 10),
                  FieldLabel(
                    'CROP PHOTO',
                    badge: _isEditing ? '(optional)' : '(required)',
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
                          for (final photo
                              in widget.existingListing!.photos.where(
                                (photo) => !_removedPhotoIds.contains(photo.id),
                              )) ...[
                            _ExistingPhotoTile(
                              key: ValueKey('listing_photo_edit_${photo.id}'),
                              url: photo.url,
                              primary: _editPrimaryId == photo.id,
                              busy: _primaryBusy && _editPrimaryId == photo.id,
                              onPrimaryTap: () => _setExistingPrimary(photo.id),
                              onRemove: () => setState(() {
                                _removedPhotoIds.add(photo.id);
                                if (_editPrimaryId == photo.id)
                                  _editPrimaryId = null;
                              }),
                            ),
                            const SizedBox(width: 12),
                          ],
                        for (var i = 0; i < _newPhotos.length; i++) ...[
                          _NewPhotoTile(
                            key: ObjectKey(_newPhotos[i]),
                            file: _newPhotos[i],
                            primary: _markedNewIndex == i,
                            onPrimaryTap: _isEditing
                                ? () => setState(() {
                                    _markedNewIndex = i;
                                    _editPrimaryId = null;
                                  })
                                : null,
                            onRemove: () => _removeNewPhoto(i),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (_photoCount < PhotoLimits.listing)
                          PhotoPlaceholder(
                            isAddButton: true,
                            onTap: _pickPhotos,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_photoCount/${PhotoLimits.listing} photos',
                    style: const TextStyle(color: Colors.black45, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  if (_scanMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _scanMessage!,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const FieldLabel(
                    'CROP NAME',
                    badge: '(required)',
                    badgeColor: Colors.black38,
                  ),
                  TextField(
                    controller: _cropLabelCtrl,
                    readOnly: true,
                    maxLength: InputLimits.cropName,
                    decoration: _inputDecoration(
                      hint: 'e.g. Cabbage, Kangkong, Tomatoes',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('CROP CATEGORY'),
                  if (_categoriesLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: FarmSpotLoader(size: 32)),
                    )
                  else if (_categoriesError != null)
                    Text(
                      _categoriesError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
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
                          label: category.id == 'OTHERS'
                              ? 'Others'
                              : category.name,
                          selected: _selectedCategoryIndex == i,
                          onTap: () => setState(() {
                            if (!_isEditing && _detectedPhoto == null) {
                              return;
                            }
                            _selectedCategoryIndex = i;
                            _categoryChosenManually = true;
                          }),
                        );
                      }),
                    ),
                  if (_selectedCategoryIndex >= 0 &&
                      _selectedCategoryIndex < _categories.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _categories[_selectedCategoryIndex].description ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
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
                    maxLength: InputLimits.description,
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
                    subtitle: _availableNowSubtitle,
                    subtitleStyle: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      height: 1.35,
                    ),
                    selected: _status == AvailabilityStatus.availableNow,
                    onTap: _setAvailableNow,
                  ),
                  SelectableOptionTile(
                    icon: Icons.schedule,
                    title: 'Soon to Harvest',
                    subtitle:
                        _status == AvailabilityStatus.soonToHarvest &&
                            _harvestDate != null
                        ? 'Ready around ${_formatDate(_harvestDate!)}'
                        : "Let buyers know it's coming",
                    selected: _status == AvailabilityStatus.soonToHarvest,
                    onTap: _selectSoonToHarvest,
                  ),
                  // "Not Available" is only offered while editing: a brand new
                  // crop is added either available or soon to harvest.
                  if (_isEditing)
                    SelectableOptionTile(
                      icon: Icons.bedtime_outlined,
                      title: 'Not Available',
                      subtitle: 'Hidden from marketplace',
                      selected: _status == AvailabilityStatus.notAvailable,
                      onTap: () => setState(() {
                        _status = AvailabilityStatus.notAvailable;
                        _harvestDate = null;
                      }),
                    ),
                  if (_status == AvailabilityStatus.soonToHarvest) ...[
                    const SizedBox(height: 18),
                    const FieldLabel('HARVEST DATE'),
                    SelectableOptionTile(
                      icon: Icons.calendar_today_outlined,
                      title: _harvestDate != null
                          ? _formatDate(_harvestDate!)
                          : 'Pick a date',
                      subtitle: _harvestDate != null
                          ? (_harvestDateSuggested
                                ? 'Suggested date. Tap to adjust for your crop.'
                                : 'Tap to change the date')
                          : 'When will the crop be ready?',
                      selected: _harvestDate != null,
                      onTap: _pickHarvestDate,
                    ),
                  ],
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
                        : (_isEditing
                              ? 'Save Changes'
                              : (widget.isFirstCrop
                                    ? 'Add Crop & Go Live'
                                    : 'Add Crop')),
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

/// Uploaded photo with a full-size preview and a cover-photo action.
class _ExistingPhotoTile extends StatelessWidget {
  final String url;
  final bool primary;
  final bool busy;
  final VoidCallback onPrimaryTap;
  final VoidCallback onRemove;

  const _ExistingPhotoTile({
    super.key,
    required this.url,
    required this.primary,
    required this.busy,
    required this.onPrimaryTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showCropPhotoPreview(context, NetworkImage(url)),
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
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey,
                    size: 24,
                  ),
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
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  tooltip: 'Remove photo',
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.cancel, color: Colors.white, size: 22),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: _PrimaryBadge(
                  primary: primary,
                  onTap: busy ? null : onPrimaryTap,
                ),
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

/// A local photo with a full-size preview before upload.
class _NewPhotoTile extends StatefulWidget {
  final XFile file;
  final bool primary;
  final VoidCallback? onPrimaryTap;
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
      onTap: () async {
        try {
          final bytes = await _bytes;
          if (context.mounted)
            await showCropPhotoPreview(context, MemoryImage(bytes));
        } catch (_) {
          // The thumbnail already shows the image load error.
        }
      },
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
                    return Image.memory(
                      snapshot.data!,
                      cacheWidth: 200,
                      fit: BoxFit.cover,
                    );
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
              if (widget.primary || widget.onPrimaryTap != null)
                Positioned(
                  top: 0,
                  left: 0,
                  child: _PrimaryBadge(
                    primary: widget.primary,
                    onTap: widget.onPrimaryTap,
                  ),
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
                    child: const Icon(
                      Icons.close,
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

/// Amber border + star badge on the photo currently marked as primary.
class _PrimaryBadge extends StatelessWidget {
  final bool primary;
  final VoidCallback? onTap;

  const _PrimaryBadge({required this.primary, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (!primary) {
      return IconButton(
        tooltip: 'Set as cover photo',
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: const Icon(Icons.star_outline, color: Colors.white, size: 20),
        style: IconButton.styleFrom(backgroundColor: Colors.black54),
      );
    }
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
