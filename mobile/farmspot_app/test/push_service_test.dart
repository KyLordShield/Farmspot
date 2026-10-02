import 'package:farmspot_app/services/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('external id mapping', () {
    // The backend sends `include_aliases: {external_id: [USR_ID]}`, so the
    // subscription has to be registered under this exact value or the push
    // matches zero devices.
    test('uses USR_ID from the cached user', () {
      expect(
        PushService.externalIdFor(<String, dynamic>{'USR_ID': '42'}),
        '42',
      );
    });

    test('coerces a numeric id', () {
      expect(PushService.externalIdFor(<String, dynamic>{'USR_ID': 42}), '42');
    });

    test('returns null when signed out so the device is detached', () {
      expect(PushService.externalIdFor(null), isNull);
      expect(PushService.externalIdFor(<String, dynamic>{}), isNull);
      expect(
        PushService.externalIdFor(<String, dynamic>{'USR_ID': '   '}),
        isNull,
      );
    });
  });

  group('app id hygiene', () {
    // The App ID is public and ships in the APK. The REST API key is the secret
    // half that signs the server's requests to OneSignal and must never end up
    // in client code — so assert the shape of both.
    test('is a well formed app id, never the REST API key', () {
      expect(PushService.appId, isNotEmpty);
      expect(
        PushService.appId,
        matches(
          RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
            r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ),
        ),
      );
    });

    test('a secret key pasted in here would be caught', () {
      // Guards the one mistake that actually matters: os_v2_app_... is a
      // credential, not an identifier.
      expect(PushService.appId, isNot(startsWith('os_v2_app_')));
      expect(PushService.appId.length, lessThan(100));
    });
  });

  group('missing native sdk', () {
    // In a test there is no Android side, so a configured build asks for an SDK
    // that is not there. That has to degrade to "no push", never to an error
    // that takes down a login or a launch.
    test('initialize never throws', () async {
      await PushService.initialize();
      expect(PushService.isReady, isFalse);
    });

    test('initialize twice is idempotent', () async {
      await PushService.initialize();
      await PushService.initialize();
      expect(PushService.isReady, isFalse);
    });

    test('login, logout and permission are no-ops', () async {
      await PushService.login('42');
      await PushService.logout();
      await PushService.requestPermissionIfNeeded();
      expect(PushService.isReady, isFalse);
    });

    test('a tapped push callback is optional', () async {
      await PushService.initialize(onNotificationOpened: () {});
      expect(PushService.isReady, isFalse);
    });
  });
}
