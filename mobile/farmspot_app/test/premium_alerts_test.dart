import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farmspot_app/models/premium_alert_settings.dart';
import 'package:farmspot_app/services/premium_alert_service.dart';
import 'package:farmspot_app/services/session_state.dart';
import 'package:farmspot_app/screens/premium/alert_settings_screen.dart';
import 'package:farmspot_app/utils/notification_icons.dart';

class FakeAlerts implements PremiumAlertsGateway {
  PremiumAlertSettings settings = const PremiumAlertSettings(
    availableCrops: ['Cabbage', 'Tomato'],
    aliases: {
      'Tomato': ['kamatis'],
    },
  );
  bool failLoad = false, failSave = false;
  int saves = 0;
  @override
  Future<PremiumAlertSettings> fetchSettings() async {
    if (failLoad) throw Exception('Load failed');
    return settings;
  }

  @override
  Future<PremiumAlertSettings> saveSettings(PremiumAlertSettings value) async {
    saves++;
    if (failSave) throw Exception('Save failed');
    return settings = value;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'test-token'});
    SessionState.instance.debugSetUser({
      'USR_ID': 'USR001',
      'USR_IS_SELLER': 1,
      'USR_IS_PREMIUM': true,
      'USR_PREMIUM_EXPIRES_AT': DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String(),
    });
  });
  tearDown(() {
    SessionState.instance.clear();
  });
  test(
    'settings service authenticates and persists choices without account IDs',
    () async {
      final api = PremiumAlertService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.url.path, '/api/premium/alert-settings');
          if (request.method == 'PUT') {
            expect(jsonDecode(request.body), {
              'enabled': true,
              'saved_farms': false,
              'buy_requests': true,
              'push_enabled': false,
              'push_frequency': 'hourly',
              'quiet_enabled': true,
              'quiet_start': '22:00',
              'quiet_end': '07:00',
              'daily_time': '09:00',
              'crop_alerts': true,
              'crops': <String>[],
            });
            return http.Response(request.body, 200);
          }
          return http.Response(
            '{"enabled":true,"saved_farms":true,"buy_requests":true}',
            200,
          );
        }),
      );
      expect((await api.fetchSettings()).savedFarms, isTrue);
      expect(
        (await api.saveSettings(
          const PremiumAlertSettings(savedFarms: false),
        )).savedFarms,
        isFalse,
      );
    },
  );
  testWidgets(
    'crop picker searches aliases and saves selections independently of saved farms',
    (tester) async {
      final fake = FakeAlerts();
      await tester.pumpWidget(
        MaterialApp(home: AlertSettingsScreen(gateway: fake)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Choose crops'), 100);
      await tester.tap(find.text('Choose crops'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'kamatis');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Tomato'));
      await tester.tap(find.text('Add selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(fake.settings.crops, ['Tomato']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(home: AlertSettingsScreen(gateway: fake)),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Tomato'), findsOneWidget);
      expect(
        notificationStyleFor('CROP_AVAILABLE').target,
        NotificationTarget.listing,
      );
    },
  );
  testWidgets(
    'phone push is opt-in with editable hourly daily and quiet controls',
    (tester) async {
      final fake = FakeAlerts();
      await tester.pumpWidget(
        MaterialApp(home: AlertSettingsScreen(gateway: fake)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Phone notifications'),
        100,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Phone notifications'),
            )
            .value,
        isFalse,
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Phone notifications'),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Grouped hourly (recommended)'),
        100,
      );
      await tester.tap(find.text('Grouped hourly (recommended)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily summary').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Summary time: 09:00'), 100);
      expect(find.text('Summary time: 09:00'), findsOneWidget);
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(fake.settings.pushEnabled, isTrue);
      expect(fake.settings.pushFrequency, 'daily');
      expect(fake.settings.quietEnabled, isTrue);
    },
  );
  test('new notification types open their actual destinations', () {
    expect(
      notificationStyleFor('SAVED_FARM_NEW_LISTING').target,
      NotificationTarget.listing,
    );
    expect(
      notificationStyleFor('SAVED_FARM_AVAILABLE').target,
      NotificationTarget.listing,
    );
    expect(
      notificationStyleFor('BUY_REQUEST_MATCH').target,
      NotificationTarget.buyRequests,
    );
  });
  testWidgets('saved farm preference is saved and retained on reopening', (
    tester,
  ) async {
    final fake = FakeAlerts();
    await tester.pumpWidget(
      MaterialApp(home: AlertSettingsScreen(gateway: fake)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(SwitchListTile, 'Saved farm updates'),
      120,
    );
    await tester.ensureVisible(
      find.widgetWithText(SwitchListTile, 'Saved farm updates'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Saved farm updates'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(fake.settings.savedFarms, isFalse);
    expect(fake.saves, 1);
    expect(find.text('Alert settings saved.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(home: AlertSettingsScreen(gateway: fake)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(SwitchListTile, 'Saved farm updates'),
      120,
    );
    await tester.ensureVisible(
      find.widgetWithText(SwitchListTile, 'Saved farm updates'),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Saved farm updates'),
          )
          .value,
      isFalse,
    );
  });
  testWidgets(
    'pause disables individual controls and failures remain visible',
    (tester) async {
      final fake = FakeAlerts()..failSave = true;
      await tester.pumpWidget(
        MaterialApp(home: AlertSettingsScreen(gateway: fake)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Business alerts'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Matching buy requests'),
        120,
      );
      await tester.ensureVisible(
        find.widgetWithText(SwitchListTile, 'Matching buy requests'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Matching buy requests'),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(find.text('Save failed'), findsOneWidget);
      expect(fake.settings.enabled, isTrue);
    },
  );
  testWidgets(
    'free sellers can control request alerts and retry failed loads',
    (tester) async {
      SessionState.instance.debugSetUser({
        'USR_ID': 'USR001',
        'USR_IS_SELLER': 1,
        'USR_IS_PREMIUM': false,
      });
      final fake = FakeAlerts()..failLoad = true;
      await tester.pumpWidget(
        MaterialApp(home: AlertSettingsScreen(gateway: fake)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Load failed'), findsOneWidget);
      fake.failLoad = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Saved farm updates'),
        120,
      );
      await tester.ensureVisible(
        find.widgetWithText(SwitchListTile, 'Saved farm updates'),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Saved farm updates'),
        120,
      );
      await tester.ensureVisible(
        find.widgetWithText(SwitchListTile, 'Saved farm updates'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Saved farm updates'),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Matching buy requests'),
            )
            .onChanged,
        isNotNull,
      );
    },
  );
}
