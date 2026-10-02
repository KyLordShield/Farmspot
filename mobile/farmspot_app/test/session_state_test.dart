import 'dart:convert';

import 'package:farmspot_app/services/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // SessionState is a process-wide singleton, so each test starts signed out
  // rather than inheriting whatever the previous one seeded.
  setUp(() => SessionState.instance.debugSetUser(null));

  group('seeding the session from disk', () {
    // Push registers its OneSignal subscription off the back of this
    // notification: a signed-in user restored on app restart has to be
    // re-attached, and a launch with no cache must not detach anyone.
    test('notifies listeners when a cached user is restored', () async {
      SharedPreferences.setMockInitialValues({
        SessionState.userPrefsKey: jsonEncode({
          'USR_ID': '42',
          'USR_IS_SELLER': 1,
        }),
      });

      var notified = 0;
      final state = SessionState.instance;
      void listener() => notified++;
      state.addListener(listener);

      await state.init();

      expect(state.isInitialised, isTrue);
      expect(state.user?['USR_ID'], '42');
      expect(state.isSeller, isTrue);
      expect(notified, 1);

      state.removeListener(listener);
    });

    test('stays silent on a signed-out launch', () async {
      SharedPreferences.setMockInitialValues({});

      var notified = 0;
      final state = SessionState.instance;
      void listener() => notified++;
      state.addListener(listener);

      await state.init();

      expect(state.isInitialised, isTrue);
      expect(state.user, isNull);
      expect(state.isLoggedIn, isFalse);
      expect(notified, 0);

      state.removeListener(listener);
    });

    test('a corrupt cache signs out instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        SessionState.userPrefsKey: 'not json',
      });

      await SessionState.instance.init();

      expect(SessionState.instance.user, isNull);
      expect(SessionState.instance.isInitialised, isTrue);
    });
  });
}
