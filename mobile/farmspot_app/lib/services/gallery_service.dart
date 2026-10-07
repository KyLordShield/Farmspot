import 'package:cross_file/cross_file.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/gallery_photo.dart';

/// Reads the device photo library with photo_manager, newest image first.
///
/// Every method never throws: an empty list means this platform/device has no
/// accessible gallery (permission denied, no plugin in tests, etc.), and the
/// screen simply hides the gallery panel.
class GalleryService {
  /// Newest-first enforced at the MediaStore/Photos query level, so "page 0"
  /// already starts from the most recent photo — the same order the native
  /// photo picker (ImagePicker elsewhere in the app) uses. Without this,
  /// photo_manager pages the album in its own order and sorting a single page
  /// later can never recover photos that sit beyond it.
  static final PMFilter _newestFirstFilter = FilterOptionGroup(
    orders: const [OrderOption(type: OrderOptionType.createDate)],
  );

  /// [limit] caps the list (3 -> the "latest three" strip; omitted returns a
  /// full page for the expanded gallery grid).
  static Future<List<GalleryPhoto>> loadPhotos({int? limit}) async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) return const [];

      // The aggregate "all photos" album, so the strip never shows an
      // arbitrary per-folder album no matter which device is in use.
      final paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        hasAll: true,
        type: RequestType.image,
        filterOption: _newestFirstFilter,
      );
      var path = paths.isEmpty ? null : paths.first;
      if (path == null) {
        final fallback = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          filterOption: _newestFirstFilter,
        );
        path = fallback.isEmpty ? null : fallback.first;
      }
      if (path == null) return const [];

      final assets = newestFirst(
        await path.getAssetListPaged(page: 0, size: limit ?? 300),
      );
      return [for (final asset in assets) _toGalleryPhoto(asset)];
    } catch (_) {
      // Permission dialog dismissed, plugin missing, gallery empty, etc.
      return const [];
    }
  }

  /// Newest first by creation time (falling back to last-modified), so the
  /// "latest three" panel really shows the most recently taken photos.
  static List<AssetEntity> newestFirst(List<AssetEntity> assets) {
    final sorted = [...assets];
    sorted.sort((a, b) {
      final byCreate = b.createDateTime.compareTo(a.createDateTime);
      return byCreate != 0
          ? byCreate
          : b.modifiedDateTime.compareTo(a.modifiedDateTime);
    });
    return sorted;
  }

  static GalleryPhoto _toGalleryPhoto(AssetEntity asset) {
    final id = asset.id;
    return GalleryPhoto(
      id: id,
      file: () async {
        final origin = await asset.originFile;
        final file = origin ?? await asset.file;
        if (file == null) {
          throw StateError('No readable file for gallery photo $id.');
        }
        return XFile(file.path);
      },
      thumb: () => asset.thumbnailDataWithSize(
        const ThumbnailSize(240, 240),
        quality: 85,
      ),
    );
  }
}