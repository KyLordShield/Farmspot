import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/models/farm_setup_data.dart';
import 'package:farmspot_app/screens/seller/farm_setup_complete_screen.dart';

void main() {
  testWidgets('shows readable address without overflow on small screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = FarmSetupData()
      ..name = 'A farm with a long name in the uplands'
      ..barangay = 'Sudlon II'
      ..latitude = 10.3796
      ..longitude = 123.7847
      ..locationAddress =
          'Sitio Maraag, Sudlon II, Cebu City, Cebu, Philippines';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: FarmSetupCompleteScreen(
          farmSetupData: data,
          frmStatus: 'PENDING_REVIEW',
        ),
      ),
    );
    expect(find.text(data.locationAddress!), findsOneWidget);
    expect(find.textContaining('123.7847'), findsNothing);
    expect(find.text('Pending review'), findsOneWidget);
    await tester.ensureVisible(find.text('Back to My Profile'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to selected barangay when address unavailable', (
    tester,
  ) async {
    final data = FarmSetupData()..barangay = 'Sudlon II';
    await tester.pumpWidget(
      MaterialApp(home: FarmSetupCompleteScreen(farmSetupData: data)),
    );
    expect(find.text('Sudlon II'), findsOneWidget);
    expect(find.text('Add a crop'), findsOneWidget);
  });
}
