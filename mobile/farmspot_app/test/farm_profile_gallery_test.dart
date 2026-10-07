import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmspot_app/models/farm_profile.dart';
import 'package:farmspot_app/screens/farm_profile_screen.dart';
import 'package:farmspot_app/screens/product_detail_screen.dart';
import 'package:farmspot_app/widgets/home_widgets.dart';

// Offline widget checks for the farm photo gallery: the banner opens the
// full-screen viewer when the farm has more than one photo, a thumbnail strip
// (with a green ring on the cover) sits under the banner, and single-photo /
// photo-less farms keep the old banner-only look with no strip and no hint.
// Offline env: Image.network falls back gracefully through errorBuilder.

final _photos = [
  FarmPhotoEntry(
    id: 'PH1',
    url: 'https://example.invalid/1.jpg',
    isPrimary: true,
  ),
  const FarmPhotoEntry(id: 'PH2', url: 'https://example.invalid/2.jpg'),
  const FarmPhotoEntry(id: 'PH3', url: 'https://example.invalid/3.jpg'),
];

CropListing _crop(String status) => CropListing(
      cropName: 'Cabbage',
      farmName: 'Mr. A Farm',
      cropType: 'Vegetables',
      status: status,
      farmId: 'FRMA',
      barangay: 'Sudlon II',
      postedLabel: 'today',
      expiresLabel: '3 days',
      distance: '0.4 km away',
    );

FarmProfileData _profile({List<FarmPhotoEntry> photos = const []}) =>
    FarmProfileData(
      id: 'FRMA',
      name: 'Mr. A Farm',
      barangay: 'Sudlon II',
      status: 'APPROVED',
      photos: photos,
      listings: [
        _crop('AVAILABLE_NOW'),
      ],
    );

Future<void> _pump(WidgetTester tester, List<FarmPhotoEntry> photos) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: FarmProfileScreen(farmId: 'FRMA', initialData: _profile(photos: photos)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('multi-photo farm: banner tap opens the full-screen viewer',
      (tester) async {
    await _pump(tester, _photos);

    expect(find.byKey(const Key('farm_photo_strip')), findsOneWidget);
    expect(find.text('3 photos • tap to view'), findsOneWidget);
    expect(find.text('Tap to view photos'), findsOneWidget);
    expect(find.byType(FullScreenPhotoViewer), findsNothing);

    await tester.tapAt(
      tester.getTopLeft(find.byKey(FarmProfileScreen.headerKey)) +
          const Offset(400, 100),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenPhotoViewer), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('viewer_close')));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPhotoViewer), findsNothing);
  });

  testWidgets('multi-photo farm: tapping a thumbnail opens the viewer there',
      (tester) async {
    await _pump(tester, _photos);

    await tester.tap(find.byKey(const ValueKey('farm_photo_thumb_2')));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenPhotoViewer), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('viewer_close')));
    await tester.pumpAndSettle();
  });

  testWidgets('single-photo farm: banner only, no strip, no hint, no viewer',
      (tester) async {
    await _pump(tester, [_photos.first]);

    expect(find.byKey(const Key('farm_photo_strip')), findsNothing);
    expect(find.text('Tap to view photos'), findsNothing);

    await tester.tapAt(
      tester.getTopLeft(find.byKey(FarmProfileScreen.headerKey)) +
          const Offset(400, 100),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPhotoViewer), findsNothing);
  });

  testWidgets('photo-less farm: placeholder icon, no strip, no viewer',
      (tester) async {
    await _pump(tester, const []);

    expect(find.byKey(const Key('farm_photo_strip')), findsNothing);
    expect(find.text('Tap to view photos'), findsNothing);
    expect(find.byIcon(Icons.agriculture), findsWidgets);
    expect(find.byType(FullScreenPhotoViewer), findsNothing);
  });
}