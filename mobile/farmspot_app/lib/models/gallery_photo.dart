import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// One image in the image-search gallery panel.
///
/// [file] yields a real, readable image file for the YOLO step; [thumb] yields
/// small preview bytes for the strip/grid tiles, or null when a thumbnail
/// could not be produced. Both are lazy so the panel only touches the photos
/// the user actually sees.
class GalleryPhoto {
  const GalleryPhoto({required this.id, required this.file, required this.thumb});

  /// Stable identity across rebuilds (also the widget key).
  final String id;

  final Future<XFile> Function() file;
  final Future<Uint8List?> Function() thumb;
}