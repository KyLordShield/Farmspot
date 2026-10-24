import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farmspot_app/models/farm_pin.dart';
import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/models/saved_farm.dart';
import 'package:farmspot_app/screens/map_screen.dart';
import 'package:farmspot_app/screens/farm_profile_screen.dart';
import 'package:farmspot_app/screens/premium/saved_farms_screen.dart';
import 'package:farmspot_app/services/saved_farms_service.dart';
import 'package:farmspot_app/services/saved_farms_state.dart';
import 'package:farmspot_app/services/session_state.dart';
import 'package:farmspot_app/widgets/save_farm_button.dart';

const farm = SavedFarm(
  id: 'FRM001',
  name: 'Maraag Farm',
  barangay: 'Sudlon',
  latitude: 10.3178,
  longitude: 123.8742,
  availableCrops: ['Cabbage'],
  upcomingCrops: ['Tomato'],
);
Map<String, dynamic> user(String id) => {
  'USR_ID': id,
  'USR_IS_PREMIUM': true,
  'USR_PREMIUM_EXPIRES_AT': DateTime.now()
      .add(const Duration(days: 30))
      .toUtc()
      .toIso8601String(),
};
Map<String, dynamic> farmJson() => {
  'id': 'FRM001',
  'name': 'Maraag Farm',
  'available': true,
  'latitude': 10.3178,
  'longitude': 123.8742,
  'available_crops': ['Cabbage'],
  'upcoming_crops': ['Tomato'],
};

class FakeSaved implements SavedFarmsGateway {
  List<SavedFarm> rows = [];
  bool failSave = false, failRemove = false;
  Completer<List<SavedFarm>>? waiting;
  Completer<SavedFarm>? waitingSave;
  int saves = 0, removes = 0;
  @override
  Future<List<SavedFarm>> fetchSavedFarms() async =>
      waiting == null ? List.of(rows) : waiting!.future;
  @override
  Future<SavedFarm> saveFarm(String id) async {
    saves++;
    if (failSave) throw Exception('Save failed');
    if (waitingSave != null) await waitingSave!.future;
    rows = [farm];
    return farm;
  }

  @override
  Future<void> removeFarm(String id) async {
    removes++;
    if (failRemove) throw Exception('Removal failed');
    rows = [];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_token': 'token'});
    SessionState.instance.debugSetUser(user('BUY001'));
  });
  tearDown(() {
    SessionState.instance.clear();
  });

  test(
    'service persists with authenticated PUT and reads real crop data',
    () async {
      final api = SavedFarmsService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer token');
          if (request.method == 'PUT')
            return http.Response(jsonEncode({'farm': farmJson()}), 200);
          return http.Response(
            jsonEncode({
              'farms': [farmJson()],
            }),
            200,
          );
        }),
      );
      expect((await api.saveFarm('FRM001')).name, 'Maraag Farm');
      expect((await api.fetchSavedFarms()).first.availableCrops, ['Cabbage']);
    },
  );

  test(
    'saved state updates only after successful saves and removals',
    () async {
      final api = FakeSaved();
      final state = SavedFarmsState(gateway: api);
      addTearDown(state.dispose);
      expect(await state.toggle('FRM001'), isTrue);
      expect(state.isSaved('FRM001'), isTrue);
      api.failRemove = true;
      await expectLater(state.toggle('FRM001'), throwsException);
      expect(state.isSaved('FRM001'), isTrue);
      api.failRemove = false;
      expect(await state.toggle('FRM001'), isFalse);
      api.failSave = true;
      await expectLater(state.toggle('FRM001'), throwsException);
      expect(state.isSaved('FRM001'), isFalse);
    },
  );

  test(
    'account switching and delayed responses cannot leak saved farms',
    () async {
      final api = FakeSaved()..waiting = Completer<List<SavedFarm>>();
      final state = SavedFarmsState(gateway: api);
      addTearDown(state.dispose);
      final loading = state.load();
      SessionState.instance.applyUser(user('BUY002'));
      final check = expectLater(loading, throwsException);
      api.waiting!.complete([farm]);
      await check;
      expect(state.farms, isEmpty);
      api.waiting = null;
      await state.load();
      expect(state.farms, isEmpty);
    },
  );

  test(
    'a delayed refresh cannot undo a successful save in local state',
    () async {
      final api = FakeSaved();
      final state = SavedFarmsState(gateway: api);
      addTearDown(state.dispose);
      await state.load();
      api.waitingSave = Completer<SavedFarm>();
      final saving = state.toggle('FRM001');
      await Future<void>.delayed(Duration.zero);
      api.waiting = Completer<List<SavedFarm>>();
      final refresh = state.load(refresh: true);
      api.waitingSave!.complete(farm);
      await saving;
      api.waiting!.complete([]);
      await refresh;
      expect(state.isSaved('FRM001'), isTrue);
    },
  );

  Future<void> cleanup(WidgetTester tester, SavedFarmsState state) async {
    SessionState.instance.clear();
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  }

  testWidgets(
    'shared heart buttons stay synchronized and recover from failure',
    (tester) async {
      final api = FakeSaved();
      final state = SavedFarmsState(gateway: api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SaveFarmButton(farmId: 'FRM001', savedFarms: state),
                SaveFarmButton(farmId: 'FRM001', savedFarms: state),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save farm').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unsave farm'), findsNWidgets(2));
      api.failRemove = true;
      await tester.tap(find.byTooltip('Unsave farm').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Unsave farm'), findsNWidgets(2));
      expect(find.text('Removal failed'), findsOneWidget);
      await cleanup(tester, state);
    },
  );

  testWidgets('Saved Farms displays real crops and removes a saved farm', (
    tester,
  ) async {
    final api = FakeSaved()..rows = [farm];
    final state = SavedFarmsState(gateway: api);
    await tester.pumpWidget(
      MaterialApp(home: SavedFarmsScreen(savedFarms: state)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Maraag Farm'), findsOneWidget);
    expect(find.text('Cabbage'), findsOneWidget);
    expect(find.textContaining('Soon to harvest: Tomato'), findsOneWidget);
    expect(find.textContaining('Usually responds'), findsNothing);
    await tester.tap(find.byTooltip('Unsave farm'));
    await tester.pumpAndSettle();
    expect(find.text('No saved farms yet'), findsOneWidget);
    await cleanup(tester, state);
  });

  testWidgets('farm profile heart saves the actual farm', (tester) async {
    final api = FakeSaved();
    final state = SavedFarmsState(gateway: api);
    await tester.pumpWidget(
      MaterialApp(
        home: FarmProfileScreen(
          farmId: 'FRM001',
          savedFarms: state,
          initialData: FarmProfileData(id: 'FRM001', name: 'Maraag Farm'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('Save farm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.isSaved('FRM001'), isTrue);
    await cleanup(tester, state);
  });

  testWidgets(
    'map heart saves the selected farm instead of opening a mock list',
    (tester) async {
      final api = FakeSaved();
      final state = SavedFarmsState(gateway: api);
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            savedFarms: state,
            loadFarms: () async => const [
              FarmPin(
                id: 'FRM001',
                name: 'Maraag Farm',
                latitude: 10.3178,
                longitude: 123.8742,
              ),
            ],
            loadPosition: () async => const LatLng(10.3178, 123.8742),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.location_on).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Save farm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.isSaved('FRM001'), isTrue);
      expect(find.byType(SavedFarmsScreen), findsNothing);
      await cleanup(tester, state);
    },
  );
}
