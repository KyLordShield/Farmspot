import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/farm_setup_data.dart';
import 'package:farmspot_app/screens/seller/farm_setup_location_screen.dart';
import 'package:farmspot_app/screens/seller/farm_setup_verify_screen.dart';

/// Replacement so the screen does not spin on unavailable GPS, matching the
/// fake used by the location-screen tests.
class _FakeGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async =>
      throw MissingPluginException();

  @override
  Future<LocationPermission> checkPermission() async =>
      throw MissingPluginException();

  @override
  Future<LocationPermission> requestPermission() async =>
      throw MissingPluginException();

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async =>
      throw MissingPluginException();
}

Future<void> _pumpVerifyScreen(
  WidgetTester tester,
  FarmSetupData data,
) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      home: FarmSetupVerifyScreen(farmSetupData: data),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('verify step shows two required document boxes', (tester) async {
    await _pumpVerifyScreen(tester, FarmSetupData());

    expect(find.text('VALID ID'), findsOneWidget);
    expect(find.text('Government ID'), findsOneWidget);
    expect(find.text('Upload'), findsNWidgets(2),
        reason: 'both the ID and the certificate start un-uploaded');
    expect(find.text('Farm Certificate/Permit'), findsOneWidget);
    // No "(optional)" badge anywhere in step 2.
    expect(find.text('(optional)'), findsNothing);
  });

  testWidgets('Next is blocked until BOTH documents are uploaded',
      (tester) async {
    final data = FarmSetupData();
    await _pumpVerifyScreen(tester, data);

    await tester.tap(find.text('Next: Pin Farm Location'));
    await tester.pump();

    expect(
      find.textContaining('Please upload both your valid ID'),
      findsOneWidget,
      reason: 'with no documents the wizard must refuse to advance',
    );
    expect(find.byType(FarmSetupLocationScreen), findsNothing);

    // Uploading only the ID still blocks.
    data
      ..photos = []
      ..verificationDocument = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'id.jpg',
      );
    await tester.tap(find.text('Next: Pin Farm Location'));
    await tester.pump();

    expect(
      find.textContaining('Please upload both your valid ID'),
      findsWidgets,
      reason: 'one of the two documents alone is still incomplete',
    );
    expect(find.byType(FarmSetupLocationScreen), findsNothing);

    // Both present -> the wizard moves to the location step.
    data.farmCertificate = XFile.fromData(
      Uint8List.fromList([4, 5, 6]),
      name: 'cert.jpg',
    );
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: FarmSetupVerifyScreen(farmSetupData: data),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _FakeGeolocator();
    addTearDown(() => GeolocatorPlatform.instance = original);

    await tester.tap(find.text('Next: Pin Farm Location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FarmSetupLocationScreen), findsOneWidget,
        reason: 'both documents present must open the location step');
  });
}