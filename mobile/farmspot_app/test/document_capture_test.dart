import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/services/live_camera.dart';
import 'package:farmspot_app/screens/seller/document_capture_screen.dart';

class FakeCamera implements LiveCamera {
  bool disposed = false;
  bool fail = false;
  @override
  Widget buildPreview() => const Text('Live preview');
  @override
  Future<XFile?> capture() async {
    if (fail) throw StateError('Camera busy');
    return XFile('document.jpg');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<LiveCamera?> flip() async => null;
}

void main() {
  testWidgets('camera is released on background and reopened on resume', (
    tester,
  ) async {
    final cameras = <FakeCamera>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentCaptureScreen(
          openCamera: () async {
            final camera = FakeCamera();
            cameras.add(camera);
            return camera;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(cameras.first.disposed, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cameras.length, 2);
    expect(find.text('Live preview'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(cameras.last.disposed, isTrue);
  });

  testWidgets('camera closes before returning the photo for OCR', (
    tester,
  ) async {
    final camera = FakeCamera();
    XFile? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<XFile>(
                MaterialPageRoute(
                  builder: (_) =>
                      DocumentCaptureScreen(openCamera: () async => camera),
                ),
              );
              expect(camera.disposed, isTrue);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Live preview'), findsOneWidget);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(result?.path, 'document.jpg');
    expect(camera.disposed, isTrue);
  });

  testWidgets('permission failure offers retry without external camera', (
    tester,
  ) async {
    final camera = FakeCamera();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentCaptureScreen(
          openCamera: () async {
            return ++attempts == 1 ? null : camera;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry camera'), findsOneWidget);
    await tester.tap(find.text('Retry camera'));
    await tester.pumpAndSettle();
    expect(find.text('Live preview'), findsOneWidget);
    camera.fail = true;
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not take the photo. Please try again.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    expect(camera.disposed, isTrue);
  });
}
