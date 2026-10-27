import 'photo_moderation_gate.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/listing.dart';
import '../services/listing_service.dart';
import '../theme.dart';
import '../utils/photo_limits.dart';

/// Opens the renewal sheet and returns the renewed listing, or null if the
/// seller backed out.
Future<Listing?> showRenewListingSheet(
  BuildContext context, {
  required Listing listing,
  Future<Listing> Function({
    required String listingId,
    required List<XFile> photos,
    required String status,
    DateTime? harvestDate,
    int primaryIndex,
  })?
  renew,
  Future<List<XFile>> Function(BuildContext, List<XFile>) moderatePhotos =
      screenPhotos,
  Future<XFile?> Function()? capturePhoto,
}) {
  return showModalBottomSheet<Listing>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RenewListingSheet(
      listing: listing,
      renew: renew,
      capturePhoto: capturePhoto,
      moderatePhotos: moderatePhotos,
    ),
  );
}

/// A renewal is a claim that the crop is still available, so it needs fresh
/// photos and its own confirmation. The camera is opened directly with no
/// gallery option: reusing an old gallery image is the exact thing the renewal
/// rule is meant to stop.
///
/// Renewal replaces the entire gallery — an expired listing's old photos are
/// last week's crop, and mixing them with a fresh primary would show buyers
/// stale produce beside today's. The seller can take several photos and star
/// the one that should be the thumbnail.
class RenewListingSheet extends StatefulWidget {
  final Future<List<XFile>> Function(BuildContext, List<XFile>) moderatePhotos;

  final Listing listing;

  /// Injectable for tests; defaults to the real API.
  final Future<Listing> Function({
    required String listingId,
    required List<XFile> photos,
    required String status,
    DateTime? harvestDate,
    int primaryIndex,
  })?
  renew;

  /// Injectable for tests; defaults to the device camera.
  final Future<XFile?> Function()? capturePhoto;

  const RenewListingSheet({
    super.key,
    this.moderatePhotos = screenPhotos,
    required this.listing,
    this.renew,
    this.capturePhoto,
  });

  static const Key captureKey = Key('renew-capture-photo');
  static const Key submitKey = Key('renew-submit');
  static const Key dateKey = Key('renew-harvest-date');

  /// The tile for one captured photo. Tapping it makes that photo the primary.
  static Key photoKey(int index) => ValueKey('renew-photo-$index');

  /// The small remove control on one captured photo.
  static Key removePhotoKey(int index) => ValueKey('renew-remove-photo-$index');

  @override
  State<RenewListingSheet> createState() => _RenewListingSheetState();
}

class _RenewListingSheetState extends State<RenewListingSheet> {
  final ImagePicker _picker = ImagePicker();

  final List<_CapturedPhoto> _photos = [];
  int _primaryIndex = 0;
  String _status = 'AVAILABLE_NOW';
  DateTime? _harvestDate;
  bool _submitting = false;
  bool _capturing = false;
  String? _error;

  bool get _isSoon => _status == 'SOON_TO_HARVEST';

  bool get _canSubmit =>
      _photos.isNotEmpty &&
      (!_isSoon || _harvestDate != null) &&
      !_submitting &&
      !_capturing;

  String get _cropLabel =>
      widget.listing.cropIcon ?? widget.listing.categoryName ?? 'crop';

  @override
  void initState() {
    super.initState();

    // Keep the listing's current intent where it is still meaningful. A row
    // that lists:expire has already flipped to NOT_AVAILABLE has no safe status
    // to preserve, so renewal defaults to Available Now.
    if (widget.listing.status == 'SOON_TO_HARVEST') {
      _status = 'SOON_TO_HARVEST';
      _harvestDate = _parseHarvestDate(widget.listing.harvestDate);
    }
  }

  DateTime? _parseHarvestDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;

    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final startOfDate = DateTime(parsed.year, parsed.month, parsed.day);
    return startOfDate.isBefore(startOfToday) ? null : startOfDate;
  }

  Future<void> _capture() async {
    if (_submitting || _capturing) return;
    if (_photos.length >= PhotoLimits.listing) {
      setState(
        () => _error =
            'Maximum 5 photos per listing. Remove a photo before adding more.',
      );
      return;
    }
    setState(() {
      _error = null;
      _capturing = true;
    });

    try {
      final captured = widget.capturePhoto != null
          ? await widget.capturePhoto!()
          : await _picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 70,
              maxWidth: 1600,
              maxHeight: 1600,
            );

      if (captured == null || !mounted) return;

      final accepted = await widget.moderatePhotos(context, [captured]);
      if (!mounted || accepted.isEmpty) return;
      final bytes = await captured.readAsBytes();
      if (!mounted) return;

      setState(() {
        _photos.add(_CapturedPhoto(file: captured, bytes: bytes));
        if (_photos.length == 1) _primaryIndex = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Could not open the camera. Allow camera access and try again.';
      });
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _markPrimary(int index) {
    if (_submitting || index < 0 || index >= _photos.length) return;
    setState(() => _primaryIndex = index);
  }

  void _removePhoto(int index) {
    if (_submitting || index < 0 || index >= _photos.length) return;

    setState(() {
      _photos.removeAt(index);

      if (_photos.isEmpty) {
        _primaryIndex = 0;
      } else if (index < _primaryIndex) {
        _primaryIndex -= 1;
      } else if (index == _primaryIndex && _primaryIndex >= _photos.length) {
        _primaryIndex = _photos.length - 1;
      }
    });
  }

  Future<void> _pickHarvestDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _harvestDate ?? today.add(const Duration(days: 1));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 2)),
      helpText: 'When will this crop be ready?',
      confirmText: 'Set',
      cancelText: 'Cancel',
    );

    if (picked == null || !mounted) return;
    setState(() => _harvestDate = picked);
  }

  Future<void> _submit() async {
    if (_photos.isEmpty || !_canSubmit) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final call = widget.renew ?? ListingService.renewListing;
      final renewed = await call(
        listingId: widget.listing.id,
        photos: _photos.map((photo) => photo.file).toList(),
        primaryIndex: _primaryIndex,
        status: _status,
        harvestDate: _isSoon ? _harvestDate : null,
      );

      if (!mounted) return;
      Navigator.of(context).pop(renewed);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Renew $_cropLabel',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkGreen,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text(
                'Take new photos of the crop today. All old photos are replaced, '
                'and the listing stays visible for another 3 days.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 14),
              _buildPhotoPicker(),
              const SizedBox(height: 16),
              const Text(
                'How should buyers see this crop?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Available now'),
                    selected: _status == 'AVAILABLE_NOW',
                    onSelected: _submitting
                        ? null
                        : (_) => setState(() => _status = 'AVAILABLE_NOW'),
                  ),
                  ChoiceChip(
                    label: const Text('Soon to harvest'),
                    selected: _status == 'SOON_TO_HARVEST',
                    onSelected: _submitting
                        ? null
                        : (_) => setState(() => _status = 'SOON_TO_HARVEST'),
                  ),
                ],
              ),
              if (_isSoon) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: RenewListingSheet.dateKey,
                  onPressed: _submitting ? null : _pickHarvestDate,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    _harvestDate == null
                        ? 'Choose harvest date'
                        : 'Ready around ${_formatDate(_harvestDate!)}',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: Color(0xFFB3261E),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  key: RenewListingSheet.submitKey,
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primaryGreen.withValues(
                      alpha: 0.35,
                    ),
                    disabledForegroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Renew for 3 days',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              if (_photos.isEmpty) ...[
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Take at least one fresh photo to continue.',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPicker() {
    if (_photos.isEmpty) {
      return InkWell(
        key: RenewListingSheet.captureKey,
        onTap: _submitting ? null : _capture,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          height: 170,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7F4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDDE6DD)),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_camera_outlined,
                size: 34,
                color: AppColors.primaryGreen,
              ),
              SizedBox(height: 8),
              Text(
                'Take a fresh photo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryGreen,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Camera only — gallery photos are not accepted',
                style: TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_photos.length}/5 photos',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _photos.length; i++) _buildPhotoTile(i),
            if (_photos.length < PhotoLimits.listing) _buildAddPhotoTile(),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _primaryIndex == 0 && _photos.length == 1
              ? 'Tap + to take another photo. The starred photo is the '
                    'thumbnail buyers see.'
              : 'Tap a photo to make it the thumbnail. All old photos are '
                    'replaced when you renew.',
          style: const TextStyle(fontSize: 11.5, color: Colors.black45),
        ),
      ],
    );
  }

  Widget _buildPhotoTile(int index) {
    final photo = _photos[index];
    final isPrimary = index == _primaryIndex;

    return GestureDetector(
      key: RenewListingSheet.photoKey(index),
      onTap: _submitting ? null : () => _markPrimary(index),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPrimary ? AppColors.primaryGreen : const Color(0xFFDDE6DD),
            width: isPrimary ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(photo.bytes, fit: BoxFit.cover),
            if (isPrimary)
              Positioned(
                left: 5,
                top: 5,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.star, size: 12, color: Colors.white),
                ),
              ),
            Positioned(
              right: 3,
              top: 3,
              child: GestureDetector(
                key: RenewListingSheet.removePhotoKey(index),
                onTap: _submitting ? null : () => _removePhoto(index),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 13, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddPhotoTile() {
    return InkWell(
      key: RenewListingSheet.captureKey,
      onTap: _submitting ? null : _capture,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDE6DD)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              size: 24,
              color: AppColors.primaryGreen,
            ),
            SizedBox(height: 4),
            Text(
              'Add photo',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// One captured image held in memory until the seller submits: the [file] is
/// what gets uploaded, and [bytes] is what the preview renders without another
/// disk read.
class _CapturedPhoto {
  final XFile file;
  final Uint8List bytes;

  const _CapturedPhoto({required this.file, required this.bytes});
}
