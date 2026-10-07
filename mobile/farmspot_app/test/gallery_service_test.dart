import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:farmspot_app/services/gallery_service.dart';

/// Creates an [AssetEntity] with just enough fields for the sorter.
AssetEntity _asset(String id, {int? create, int? modified}) => AssetEntity(
  id: id,
  typeInt: 1, // RequestType.image
  width: 10,
  height: 10,
  createDateSecond: create,
  modifiedDateSecond: modified,
);

void main() {
  group('GalleryService.newestFirst', () {
    test('orders by creation time, newest first', () {
      final sorted = GalleryService.newestFirst([
        _asset('old', create: 1000),
        _asset('recent', create: 3000),
        _asset('mid', create: 2000),
      ]);

      expect(sorted.map((a) => a.id).toList(), ['recent', 'mid', 'old']);
    });

    test('falls back to last-modified when creation times match', () {
      final sorted = GalleryService.newestFirst([
        _asset('a', create: 5000, modified: 1000),
        _asset('b', create: 5000, modified: 2000),
      ]);

      expect(sorted.first.id, 'b');
    });

    test('leaves the caller list untouched', () {
      final list = [_asset('x', create: 1), _asset('y', create: 2)];
      GalleryService.newestFirst(list);
      expect(list.map((a) => a.id).toList(), ['x', 'y']);
    });
  });
}