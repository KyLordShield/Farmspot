import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/crop_category.dart';
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

  const AddCropScreen({super.key, this.isFirstCrop = false, this.farmId});

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen> {
  final _picker = ImagePicker();
  final _cropLabelCtrl = TextEditingController();

  bool _farmsLoading = true;
  List<Map<String, dynamic>> _farms = [];
  String? _selectedFarmId;

  bool _categoriesLoading = true;
  List<CropCategory> _categories = [];
  String? _categoriesError;
  int _selectedCategoryIndex = -1;

  AvailabilityStatus _status = AvailabilityStatus.availableNow;
  DateTime? _harvestDate;
  XFile? _photo;

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    if (!widget.isFirstCrop) {
      _loadFarms();
    } else {
      _farmsLoading = false;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _cropLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFarms() async {
    final farms = await FarmService.getFarms();
    if (!mounted) return;
    setState(() {
      _farmsLoading = false;
      _farms = farms;
      // Auto-select the first farm (covers the common single-farm case) but
      // keep every farm visible/selectable in the UI.
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
        _selectedCategoryIndex = categories.isEmpty ? -1 : 0;
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

  Future<void> _pickPhoto() async {
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
      setState(() {
        _photo = picked;
        _submitError = null;
      });
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
      final created = await ListingService.createListing(
        farmId: farmId,
        categoryId: category.id,
        status: _status.backendValue,
        cropIcon: label.isEmpty ? null : label,
        harvestDate: _harvestDate,
        photo: _photo,
      );

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
              title: widget.isFirstCrop ? 'Add First Crop' : 'Add Crop',
              subtitle: widget.isFirstCrop
                  ? 'What are you selling this harvest?'
                  : 'Pick farm, crop, and availability',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  if (!widget.isFirstCrop) ...[
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_photo != null) ...[
                          _SinglePhotoTile(
                            key: ObjectKey(_photo),
                            file: _photo!,
                            onRemove: () => setState(() => _photo = null),
                          ),
                          const SizedBox(width: 12),
                        ],
                        PhotoPlaceholder(isAddButton: true, onTap: _pickPhoto),
                      ],
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
                        ? 'Adding Crop...'
                        : (widget.isFirstCrop
                            ? 'Add Crop & Go Live'
                            : 'Add Crop'),
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

/// Single-photo preview with a remove ("X") affordance. Reads the picker's
/// XFile as bytes (web-safe) and renders via Image.memory.
class _SinglePhotoTile extends StatefulWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _SinglePhotoTile({
    super.key,
    required this.file,
    required this.onRemove,
  });

  @override
  State<_SinglePhotoTile> createState() => _SinglePhotoTileState();
}

class _SinglePhotoTileState extends State<_SinglePhotoTile> {
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