import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:latlong2/latlong.dart';

import 'package:farmspot_app/models/gallery_photo.dart';
import 'package:farmspot_app/models/listing.dart';
import 'package:farmspot_app/screens/image_search_screen.dart';
import 'package:farmspot_app/screens/search_results_screen.dart';
import 'package:farmspot_app/services/image_detect_service.dart';
import 'package:farmspot_app/services/live_camera.dart';

/// Buyer position used by the fixtures: Cebu City.
const _userPos = LatLng(10.3178, 123.8742);

/// A real 1x1 PNG so Image.memory can actually decode in the tiles.
final Uint8List _kPng =
    Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

class _FakeLiveCamera implements LiveCamera {
  _FakeLiveCamera({this.shot});

  final XFile? shot;
  int captures = 0;

  @override
  Widget buildPreview() =>
      const ColoredBox(key: Key('fake-preview'), color: Colors.black);

  @override
  Future<XFile?> capture() async {
    captures++;
    return shot;
  }

  @override
  Future<LiveCamera?> flip() async => null;

  @override
  Future<void> dispose() async {}
}

GalleryPhoto _photo(String id) => GalleryPhoto(
  id: id,
  file: () async => XFile('/tmp/$id.jpg'),
  thumb: () async => _kPng,
);

Listing _listing(String id, String crop, String farm, {String? farmId}) {
  return Listing(
    id: id,
    cropIcon: crop,
    farmName: farm,
    farmId: farmId,
    status: 'AVAILABLE_NOW',
    categoryName: 'Vegetables',
  );
}

Future<void> pumpLive(
  WidgetTester tester, {
  LiveCamera? camera,
  List<GalleryPhoto> recents = const [],
  List<GalleryPhoto> all = const [],
  Future<List<DetectedCrop>> Function(XFile)? detect,
  Future<List<Listing>> Function(String term)? loadResults,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: ImageSearchScreen(
        createCamera: () async => camera,
        loadPhotos: ({int? limit}) async {
          final source = all.isEmpty ? recents : all;
          return limit == null ? source : source.take(limit).toList();
        },
        detect: detect ?? (_) async => const [],
        loadResults: loadResults,
        loadFarms: () async => const [],
        loadBuyerPosition: () async => _userPos,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('ImageSearchScreen live camera', () {
    testWidgets('auto-starts the camera: live preview, shutter and recent '
        'strip, no Camera/Gallery buttons', (tester) async {
      final camera = _FakeLiveCamera();
      final recents = [_photo('p1'), _photo('p2'), _photo('p3')];
      final all = [...recents, _photo('p4'), _photo('p5')];

      await pumpLive(tester, camera: camera, recents: recents, all: all);

      expect(find.byKey(const Key('fake-preview')), findsOneWidget);
      expect(find.byKey(const Key('image-search-shutter')), findsOneWidget);
      expect(find.text('Recent photos'), findsOneWidget);
      for (final photo in recents) {
        expect(find.byKey(ValueKey('gallery-photo-${photo.id}')), findsOneWidget);
      }
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Gallery'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the "Identify crop" bar is pinned to the top of the camera, '
        'not centered mid-screen', (tester) async {
      await pumpLive(tester, camera: _FakeLiveCamera());

      final titleY = tester.getTopLeft(find.text('Identify crop')).dy;
      expect(titleY, lessThan(100),
          reason: 'title should be in the top strip, got dy=$titleY');

      // The behind-the-bar scrim only dims the top strip, not the whole camera.
      final scrim = tester.widgetList(
        find.byWidgetPredicate(
          (w) => w is Container && w.color == Colors.black26,
        ),
      );
      expect(scrim, isNotEmpty);
      final scrimBottom = tester
          .getRect(find.byWidgetPredicate(
            (w) => w is Container && w.color == Colors.black26,
          ))
          .bottom;
      expect(scrimBottom, lessThan(120),
          reason: 'dim strip should hug the top bar, got bottom=$scrimBottom');

      expect(find.byKey(const Key('fake-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the gallery panel when the library is unavailable', (
      tester,
    ) async {
      await pumpLive(tester, camera: _FakeLiveCamera());

      expect(find.text('Recent photos'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no camera -> clean unavailable message, no picker buttons', (
      tester,
    ) async {
      await pumpLive(tester, camera: null);

      expect(find.textContaining("Camera isn't available"), findsOneWidget);
      expect(find.text('Camera'), findsNothing);
      expect(find.text('Gallery'), findsNothing);
      expect(find.byKey(const Key('image-search-shutter')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dragging the handle up expands into the full gallery grid and '
        'down collapses again', (tester) async {
      final recents = [_photo('p1'), _photo('p2'), _photo('p3')];
      final all = [...recents, _photo('p4'), _photo('p5')];

      await pumpLive(tester, camera: _FakeLiveCamera(), recents: recents, all: all);

      expect(find.byKey(const Key('image-search-gallery-grid')), findsNothing);

      await tester.drag(
        find.byKey(const Key('gallery-sheet-handle')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('image-search-gallery-grid')), findsOneWidget);
      expect(find.text('All photos'), findsOneWidget);
      expect(find.byKey(const ValueKey('gallery-photo-p4')), findsOneWidget);
      expect(find.byKey(const ValueKey('gallery-photo-p5')), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('image-search-gallery-grid')), findsNothing);
      expect(find.text('Recent photos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a recent photo identifies it and jumps to results', (
      tester,
    ) async {
      final searched = <String>[];
      final recents = [_photo('p1'), _photo('p2'), _photo('p3')];

      await pumpLive(
        tester,
        camera: _FakeLiveCamera(),
        recents: recents,
        detect: (_) async =>
            [DetectedCrop(name: 'Carrots', confidence: 0.94)],
        loadResults: (term) async {
          searched.add(term);
          return [_listing('L-$term', term, "A's Farm", farmId: 'F1')];
        },
      );

      await tester.tap(find.byKey(const ValueKey('gallery-photo-p2')));
      await tester.pump();
      expect(find.text('Scanning Image'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SearchResultsScreen), findsOneWidget);
      expect(searched, contains('Carrots'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the shutter snaps a photo and identifies it', (tester) async {
      final searched = <String>[];
      final camera = _FakeLiveCamera(shot: XFile('/tmp/shot.jpg'));

      await pumpLive(
        tester,
        camera: camera,
        detect: (_) async =>
            [DetectedCrop(name: 'Carrots', confidence: 0.94)],
        loadResults: (term) async {
          searched.add(term);
          return [_listing('L-$term', term, "A's Farm", farmId: 'F1')];
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('image-search-shutter')));
      await tester.pump();
      expect(find.text('Scanning Image'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SearchResultsScreen), findsOneWidget);
      expect(searched, contains('Carrots'));
      expect(camera.captures, 1);
      expect(tester.takeException(), isNull);
    });
  });
}