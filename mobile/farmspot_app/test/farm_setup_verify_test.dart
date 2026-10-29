import 'package:farmspot_app/legal/legal.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmspot_app/models/farm_setup_data.dart';
import 'package:farmspot_app/screens/seller/farm_setup_details_screen.dart';
import 'package:farmspot_app/screens/seller/farm_setup_location_screen.dart';
import 'package:farmspot_app/screens/seller/farm_setup_verify_screen.dart';
import 'package:farmspot_app/widgets/seller_widgets.dart';

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
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => throw MissingPluginException();
}

Future<void> _pumpVerifyScreen(WidgetTester tester, FarmSetupData data) async {
  SharedPreferences.setMockInitialValues({
    'user_data': '{"USR_NAME":"Juan Dela Cruz"}',
  });
  await tester.pumpWidget(
    MaterialApp(
      home: FarmSetupVerifyScreen(
        farmSetupData: data,
        confirmDocumentPrivacy: () async => true,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await LegalService.catalog();
  });
  testWidgets('verification Next stays blocked without the privacy agreement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_data': '{"USR_NAME":"Juan Dela Cruz"}',
    });
    final data = FarmSetupData()
      ..verificationDocument = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'id.jpg',
      )
      ..farmCertificate = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'permit.jpg',
      );
    await tester.pumpWidget(
      MaterialApp(home: FarmSetupVerifyScreen(farmSetupData: data)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Next: Pin Farm Location'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next: Pin Farm Location'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Please read and agree to the ID & Permit Privacy Notice',
      ),
      findsOneWidget,
    );
    expect(find.byType(FarmSetupLocationScreen), findsNothing);
  });
  testWidgets(
    'verification cannot start capture before document privacy agreement',
    (tester) async {
      var captures = 0;
      SharedPreferences.setMockInitialValues({
        'user_data': '{"USR_NAME":"Juan Dela Cruz"}',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: FarmSetupVerifyScreen(
            farmSetupData: FarmSetupData(),
            captureDocument: () async {
              captures++;
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Take photo').first);
      await tester.tap(find.text('Take photo').first);
      await tester.pumpAndSettle();
      expect(captures, 0);
      expect(
        find.textContaining(
          'Please read and agree to the ID & Permit Privacy Notice',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('verify step shows two required document boxes', (tester) async {
    await _pumpVerifyScreen(tester, FarmSetupData());

    expect(find.text('VALID ID'), findsOneWidget);
    expect(find.text('Government ID'), findsOneWidget);
    expect(
      find.text('Take photo'),
      findsNWidgets(2),
      reason: 'both the ID and the certificate start un-uploaded',
    );
    expect(find.text('Farm Certificate/Permit'), findsOneWidget);
    // No "(optional)" badge anywhere in step 2.
    expect(find.text('(optional)'), findsNothing);
  });

  testWidgets('uploaded documents show a clear "Uploaded" indicator', (
    tester,
  ) async {
    final data = FarmSetupData()
      ..verificationDocument = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'id.jpg',
      )
      ..farmCertificate = XFile.fromData(
        Uint8List.fromList([4, 5, 6]),
        name: 'cert.jpg',
      );

    await _pumpVerifyScreen(tester, data);

    expect(
      find.text('Uploaded'),
      findsNWidgets(2),
      reason: 'each attached document must show the uploaded pill',
    );
    expect(
      find.byIcon(Icons.check_circle),
      findsNWidgets(2),
      reason: 'the subtitle carries a green check as a second cue',
    );
    expect(find.text('Retake photo'), findsNWidgets(2));
    expect(find.text('Upload'), findsNothing);
  });

  testWidgets('Next is blocked until BOTH documents are uploaded', (
    tester,
  ) async {
    final data = FarmSetupData();
    await _pumpVerifyScreen(tester, data);

    await tester.scrollUntilVisible(
      find.text('Next: Pin Farm Location'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next: Pin Farm Location'));
    await tester.pump();

    expect(
      find.textContaining('Please photograph both your valid ID'),
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
    await tester.scrollUntilVisible(
      find.text('Next: Pin Farm Location'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next: Pin Farm Location'));
    await tester.pump();

    expect(
      find.textContaining('Please photograph both your valid ID'),
      findsWidgets,
      reason: 'one of the two documents alone is still incomplete',
    );
    expect(find.byType(FarmSetupLocationScreen), findsNothing);

    data.verificationDocumentText =
        'PHILIPPINE IDENTIFICATION NAME Juan Dela Cruz ADDRESS Manila';
    data.farmCertificateText =
        'BUSINESS PERMIT NAME Juan Dela Cruz FARM Manila';
    // Both present -> the wizard moves to the location step.
    data.farmCertificate = XFile.fromData(
      Uint8List.fromList([4, 5, 6]),
      name: 'cert.jpg',
    );
    SharedPreferences.setMockInitialValues({
      'user_data': '{"USR_NAME":"Juan Dela Cruz"}',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FarmSetupVerifyScreen(
          farmSetupData: data,
          confirmDocumentPrivacy: () async => true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _FakeGeolocator();
    addTearDown(() => GeolocatorPlatform.instance = original);

    await tester.scrollUntilVisible(
      find.text('Next: Pin Farm Location'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next: Pin Farm Location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byType(FarmSetupLocationScreen),
      findsOneWidget,
      reason: 'both documents present must open the location step',
    );
  });

  testWidgets('capture checks reject random images and name mismatches', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_data': '{"USR_NAME":"Juan Dela Cruz"}',
    });
    final data = FarmSetupData();
    var text = 'A random photo of a tree';
    await tester.pumpWidget(
      MaterialApp(
        home: FarmSetupVerifyScreen(
          farmSetupData: data,
          confirmDocumentPrivacy: () async => true,
          captureDocument: () async =>
              XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'id.jpg'),
          readDocument: (_) async => text,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo').first);
    await tester.pumpAndSettle();
    expect(data.verificationDocument, isNull);
    expect(
      find.textContaining('Could not read a supported government ID'),
      findsOneWidget,
    );
    text = 'PHILIPPINE IDENTIFICATION NAME Pedro Santos ADDRESS Manila';
    await tester.tap(find.text('Take photo').first);
    await tester.pumpAndSettle();
    expect(data.verificationDocument, isNull);
    // Clear the previous queued snackbar before checking the mismatch message.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('The ID name must match'), findsOneWidget);
    text = 'PHILIPPINE IDENTIFICATION NAME Juan Dela Cruz ADDRESS Manila';
    await tester.tap(find.text('Take photo').first);
    await tester.pumpAndSettle();
    expect(data.verificationDocument, isNotNull);
    expect(data.verificationDocumentText, text);
    expect(find.text('Photo Library'), findsNothing);
  });

  testWidgets('cancel and recognition failure leave documents unset', (
    tester,
  ) async {
    final data = FarmSetupData();
    var cancelled = true;
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: FarmSetupVerifyScreen(
          farmSetupData: data,
          confirmDocumentPrivacy: () async => true,
          captureDocument: () async => cancelled ? null : XFile('id.jpg'),
          readDocument: (_) async => throw Exception('OCR unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo').first);
    await tester.pumpAndSettle();
    expect(data.verificationDocument, isNull);
    cancelled = false;
    await tester.tap(find.text('Take photo').first);
    await tester.pumpAndSettle();
    expect(data.verificationDocument, isNull);
    expect(find.textContaining('Unable to capture or read'), findsOneWidget);
  });

  // ------------------------------------------- adding a second farm onward

  testWidgets('a second farm skips the identity step entirely', (tester) async {
    final original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _FakeGeolocator();
    addTearDown(() => GeolocatorPlatform.instance = original);

    final data = FarmSetupData()
      ..name = 'South Field'
      ..description = 'A second plot down the road.'
      ..barangay = 'Barangay Dos'
      ..photos = [
        XFile.fromData(Uint8List.fromList([7, 8, 9]), name: 'field.jpg'),
      ];

    SharedPreferences.setMockInitialValues({
      'user_data': '{"USR_NAME":"Juan Dela Cruz"}',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FarmSetupDetailsScreen(
          farmSetupData: data,
          isAdditionalFarm: true,
        ),
      ),
    );
    await tester.pump();

    // The step counter must not promise a step 2 that no longer happens.
    final progress = tester.widget<StepProgress>(
      find.descendant(
        of: find.byType(FarmSetupDetailsScreen),
        matching: find.byType(StepProgress),
      ),
    );
    expect(progress.step, 1);
    expect(
      progress.totalSteps,
      2,
      reason: 'a second farm has two steps, not three',
    );
    await tester.scrollUntilVisible(
      find.text('Next: Pin Farm Location'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Next: Pin Farm Location'), findsOneWidget);
    expect(find.text('Next: Verify Identity'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Next: Pin Farm Location'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next: Pin Farm Location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byType(FarmSetupLocationScreen),
      findsOneWidget,
      reason:
          'a second farm inherits its documents, so it must not be '
          'asked to upload them again',
    );
    expect(find.byType(FarmSetupVerifyScreen), findsNothing);

    final location = tester.widget<StepProgress>(
      find.descendant(
        of: find.byType(FarmSetupLocationScreen),
        matching: find.byType(StepProgress),
      ),
    );
    expect(location.step, 2);
    expect(
      location.totalSteps,
      2,
      reason:
          'the location step is the second of two, not the third of '
          'three, or the skipped step looks like a bug',
    );
  });
}
