import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/widgets/seller_widgets.dart';

import 'photo_fixture.dart';

/// A valid 1x1 transparent PNG, different from the JPEG fixture so the test
/// can tell which file the thumbnail is showing.
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

final Uint8List _firstBytes = base64Decode(tinyJpegBase64);
final Uint8List _secondBytes = base64Decode(_tinyPngBase64);

// On IO, XFile.name comes from the path (the `name` argument is ignored), so
// pass the filename as the path while keeping the in-memory bytes.
XFile _doc(String name, Uint8List bytes) =>
    XFile.fromData(bytes, path: name);

Widget _wrap(XFile file) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: UploadBox(
          icon: Icons.badge_outlined,
          title: 'Government ID',
          subtitle: 'Uploaded ${file.name}',
          buttonLabel: 'Change',
          isUploaded: true,
          previewFile: file,
          onTap: () {},
        ),
      ),
    ),
  );
}

Image _thumbnail(WidgetTester tester) => tester.widget<Image>(
      find.descendant(
        of: find.byType(UploadBox),
        matching: find.byType(Image),
      ),
    );

MemoryImage _memoryImage(Image image) {
  final provider = image.image;
  // Image.memory with cacheWidth wraps the provider in a ResizeImage.
  if (provider is ResizeImage) {
    return provider.imageProvider as MemoryImage;
  }
  return provider as MemoryImage;
}

void main() {
  testWidgets('changing the uploaded file refreshes the thumbnail',
      (tester) async {
    final first = _doc('first.jpg', _firstBytes);
    final second = _doc('second.png', _secondBytes);

    await tester.pumpWidget(_wrap(first));
    await tester.pump();
    await tester.pump();

    expect(
      _memoryImage(_thumbnail(tester)).bytes,
      _firstBytes,
    );

    await tester.pumpWidget(_wrap(second));
    await tester.pump();
    await tester.pump();

    expect(find.text('Uploaded second.png'), findsOneWidget);
    expect(
      _memoryImage(_thumbnail(tester)).bytes,
      _secondBytes,
      reason: 're-picking must replace the old preview, not keep showing it',
    );
  });

  testWidgets('tapping the thumbnail opens a full preview', (tester) async {
    final file = _doc('id.jpg', _firstBytes);

    await tester.pumpWidget(_wrap(file));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('uploadPreviewThumbnail')));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('id.jpg'), findsOneWidget);
  });
}
