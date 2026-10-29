import 'dart:async';
import 'package:farmspot_app/services/camera_permission_service.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/services/live_camera.dart';
import 'package:farmspot_app/screens/seller/document_capture_screen.dart';

class FakeCamera implements LiveCamera {
  bool disposed = false;
  bool fail = false;
  int captures = 0;
  @override
  Widget buildPreview() => const Text('Live preview');
  @override
  Future<XFile?> capture() async {
    captures++;
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

class FakePermissions implements CameraPermissionGateway {
  CameraAccess access;
  CameraAccess? requestedAccess;
  int requests = 0, settings = 0;
  Future<CameraAccess> Function()? onRequest;
  FakePermissions([this.access = CameraAccess.granted]);
  @override
  Future<CameraAccess> status() async => access;
  @override
  Future<CameraAccess> request() async {
    requests++;
    return access = onRequest != null
        ? await onRequest!()
        : requestedAccess ?? access;
  }

  @override
  Future<bool> openSettings() async {
    settings++;
    return true;
  }
}

void main() {
  testWidgets('permission is requested before the camera is opened', (
    tester,
  ) async {
    final permissions = FakePermissions(CameraAccess.denied)
      ..requestedAccess = CameraAccess.granted;
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentCaptureScreen(
          permissions: permissions,
          openCamera: () async {
            expect(permissions.access, CameraAccess.granted);
            opens++;
            return FakeCamera();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(permissions.requests, 1);
    expect(opens, 1);
    expect(find.text('Live preview'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'denial blocks preview and capture until the user allows camera',
    (tester) async {
      final permissions = FakePermissions(CameraAccess.denied);
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentCaptureScreen(
            permissions: permissions,
            openCamera: () async {
              opens++;
              return FakeCamera();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(permissions.requests, 1);
      expect(find.text('Take photo'), findsNothing);
      expect(find.text('Allow camera'), findsOneWidget);
      permissions.requestedAccess = CameraAccess.granted;
      await tester.tap(find.text('Allow camera'));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(permissions.requests, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'blocked permission opens settings and rechecks access on return',
    (tester) async {
      final permissions = FakePermissions(CameraAccess.blocked);
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentCaptureScreen(
            permissions: permissions,
            openCamera: () async {
              opens++;
              return FakeCamera();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(permissions.requests, 0);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(permissions.settings, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      permissions.access = CameraAccess.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(permissions.requests, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'permission dialog lifecycle cannot open the camera before grant or request twice',
    (tester) async {
      final result = Completer<CameraAccess>();
      final permissions = FakePermissions(CameraAccess.denied)
        ..onRequest = () => result.future;
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentCaptureScreen(
            permissions: permissions,
            openCamera: () async {
              opens++;
              return FakeCamera();
            },
          ),
        ),
      );
      await tester.pump();
      expect(permissions.requests, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(opens, 0);
      result.complete(CameraAccess.granted);
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(permissions.requests, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'revocation while away closes the camera and does not auto-request permission',
    (tester) async {
      final camera = FakeCamera();
      final permissions = FakePermissions();
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DocumentCaptureScreen(
            permissions: permissions,
            openCamera: () async {
              opens++;
              return camera;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      permissions.access = CameraAccess.denied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(camera.disposed, isTrue);
      expect(opens, 1);
      expect(permissions.requests, 0);
      expect(find.text('Take photo'), findsNothing);
      expect(find.text('Allow camera'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('permission is rechecked before taking a document photo', (
    tester,
  ) async {
    final camera = FakeCamera();
    final permissions = FakePermissions();
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentCaptureScreen(
          permissions: permissions,
          openCamera: () async => camera,
        ),
      ),
    );
    await tester.pumpAndSettle();
    permissions.access = CameraAccess.denied;
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(camera.captures, 0);
    expect(camera.disposed, isTrue);
    expect(find.text('Allow camera'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('camera is released on background and reopened on resume', (
    tester,
  ) async {
    final cameras = <FakeCamera>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentCaptureScreen(
          permissions: FakePermissions(),
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
                  builder: (_) => DocumentCaptureScreen(
                    permissions: FakePermissions(),
                    openCamera: () async => camera,
                  ),
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
          permissions: FakePermissions(),
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
