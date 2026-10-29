import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:farmspot_app/services/camera_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  const gateway = DeviceCameraPermissions();
  late PermissionStatus status, requested;
  late List<int> requests;
  setUp(() {
    status = PermissionStatus.denied;
    requested = PermissionStatus.denied;
    requests = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'checkPermissionStatus') {
            expect(call.arguments, Permission.camera.value);
            return status.index;
          }
          if (call.method == 'requestPermissions') {
            requests.addAll((call.arguments as List).cast<int>());
            return {Permission.camera.value: requested.index};
          }
          throw StateError('Unexpected permission operation');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'Android remembered denial still permits a fresh OS request after settings reset',
    () async {
      status = PermissionStatus.permanentlyDenied;
      requested = PermissionStatus.granted;
      expect(await gateway.status(), CameraAccess.denied);
      expect(await gateway.request(), CameraAccess.granted);
      expect(requests, [Permission.camera.value]);
    },
  );
  test(
    'OS request that stays blocked remains blocked and requests only camera',
    () async {
      requested = PermissionStatus.permanentlyDenied;
      expect(await gateway.request(), CameraAccess.blocked);
      expect(requests, [Permission.camera.value]);
    },
  );
  test(
    'granted and iOS restricted permissions are preserved without requesting',
    () async {
      status = PermissionStatus.granted;
      expect(await gateway.status(), CameraAccess.granted);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      status = PermissionStatus.restricted;
      expect(await gateway.status(), CameraAccess.restricted);
      status = PermissionStatus.permanentlyDenied;
      expect(await gateway.status(), CameraAccess.blocked);
      expect(requests, isEmpty);
    },
  );
}
