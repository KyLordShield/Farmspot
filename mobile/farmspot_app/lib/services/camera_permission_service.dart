import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

enum CameraAccess { granted, denied, blocked, restricted }

abstract class CameraPermissionGateway {
  Future<CameraAccess> status();
  Future<CameraAccess> request();
  Future<bool> openSettings();
}

class DeviceCameraPermissions implements CameraPermissionGateway {
  const DeviceCameraPermissions();

  CameraAccess _access(permissions.PermissionStatus status) {
    if (status.isGranted) return CameraAccess.granted;
    if (status.isPermanentlyDenied) return CameraAccess.blocked;
    if (status.isRestricted) return CameraAccess.restricted;
    return CameraAccess.denied;
  }

  @override
  Future<CameraAccess> status() async {
    final access = _access(await permissions.Permission.camera.status);
    // Android can reset a past denial to "Ask every time" in Settings.
    // An explicit request is authoritative; a remembered denial must not
    // prevent that request. The camera still requires an actual grant.
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        access == CameraAccess.blocked) {
      return CameraAccess.denied;
    }
    return access;
  }

  @override
  Future<CameraAccess> request() async =>
      _access(await permissions.Permission.camera.request());
  @override
  Future<bool> openSettings() => permissions.openAppSettings();
}
