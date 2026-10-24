import 'dart:convert';
import 'package:farmspot_app/widgets/sourcing_crop_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:farmspot_app/models/sourcing.dart';
import 'package:farmspot_app/services/sourcing_service.dart';
import 'package:farmspot_app/screens/premium/sourcing_list_screen.dart';
import 'package:farmspot_app/screens/premium/sourcing_trip_screen.dart';

class FakeSourcing implements SourcingGateway {
  List<String> saved = [];
  bool failSave = false;
  LatLng? position;
  @override
  Future<SourcingList> fetchList() async => SourcingList.fromJson({
    'crops': saved,
    'available_crops': ['Cabbage', 'Tomato'],
    'crop_aliases': {
      'Tomato': ['kamatis'],
    },
  });
  @override
  Future<void> saveList(List<String> crops) async {
    if (failSave) throw Exception('Save failed');
    saved = crops;
  }

  @override
  Future<SourcingMatches> fetchMatches({LatLng? position}) async {
    this.position = position;
    return SourcingMatches.fromJson({
      'requested_crops': ['Cabbage', 'Tomato'],
      'missing_crops': ['Tomato'],
      'has_buyer_location': position != null,
      'farms': [
        {
          'id': 'FARM01',
          'name': 'Actual farm',
          'barangay': 'Sudlon',
          'latitude': null,
          'longitude': null,
          'distance_km': null,
          'matched_crops': ['Cabbage', 'Pechay'],
          'available_crops': ['Cabbage'],
          'upcoming_crops': ['Pechay'],
          'needs_confirmation': true,
        },
      ],
    });
  }
}

void main() {
  test(
    'service uses authenticated account endpoints and sends location without a radius',
    () async {
      SharedPreferences.setMockInitialValues({'auth_token': 'sourcing-token'});
      final paths = <String>[];
      final service = SourcingService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer sourcing-token');
          paths.add('${request.method} ${request.url.path}');
          if (request.method == 'GET')
            return http.Response(
              jsonEncode({
                'crops': ['Tomato'],
                'available_crops': ['Tomato'],
              }),
              200,
            );
          final body = jsonDecode(request.body);
          if (request.method == 'PUT') {
            expect(body, {
              'crops': ['Tomato'],
            });
            return http.Response('{"crops":["Tomato"]}', 200);
          }
          expect(body, {'latitude': 10.3, 'longitude': 123.9});
          return http.Response(
            jsonEncode({
              'requested_crops': ['Tomato'],
              'missing_crops': ['Tomato'],
              'farms': [],
              'has_buyer_location': true,
            }),
            200,
          );
        }),
      );
      expect((await service.fetchList()).crops, ['Tomato']);
      await service.saveList(['Tomato']);
      expect(
        (await service.fetchMatches(
          position: const LatLng(10.3, 123.9),
        )).missingCrops,
        ['Tomato'],
      );
      expect(paths, [
        'GET /api/sourcing/list',
        'PUT /api/sourcing/list',
        'POST /api/sourcing/matches',
      ]);
    },
  );
  testWidgets('loads account selection and saves changes', (tester) async {
    final gateway = FakeSourcing()..saved = ['Cabbage'];
    await tester.pumpWidget(
      MaterialApp(home: SourcingListScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    await tester.tap(find.text('Add crops'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'kamatis');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Cabbage'), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Tomato'));
    await tester.tap(find.text('Add selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save list'));
    await tester.pumpAndSettle();
    expect(gateway.saved, ['Cabbage', 'Tomato']);
  });
  testWidgets('picker cancels edits and handles a large catalog lazily', (
    tester,
  ) async {
    final catalog = List.generate(500, (i) => 'Crop $i');
    Set<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<Set<String>>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SourcingCropPicker(
                    catalog: catalog,
                    aliases: const {},
                    selected: const {'Crop 0'},
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile).evaluate().length, lessThan(30));
    await tester.enterText(find.byType(TextField), 'not found');
    await tester.pumpAndSettle();
    expect(find.text('No crops found. Try another name.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Crop 1'));
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
  testWidgets('failed save stays on list and reports error', (tester) async {
    final gateway = FakeSourcing()
      ..saved = ['Cabbage']
      ..failSave = true;
    await tester.pumpWidget(
      MaterialApp(home: SourcingListScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find matching farms'));
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsOneWidget);
    expect(find.byType(SourcingTripScreen), findsNothing);
  });
  testWidgets('real matches show missing crops and no invented distance', (
    tester,
  ) async {
    final gateway = FakeSourcing();
    await tester.pumpWidget(
      MaterialApp(
        home: SourcingTripScreen(gateway: gateway, locate: () async => null),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.position, isNull);
    expect(find.text('Actual farm'), findsOneWidget);
    expect(find.text('Available now'), findsOneWidget);
    expect(find.text('Soon to harvest'), findsOneWidget);
    expect(find.text('unavailable'), findsOneWidget);
    expect(
      find.textContaining('No available or upcoming listings for: Tomato'),
      findsOneWidget,
    );
    expect(find.text('Older listings: confirm availability.'), findsOneWidget);
    expect(find.text('View farm'), findsOneWidget);
    final directions = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Directions'),
    );
    expect(directions.onPressed, isNull);
  });
}
