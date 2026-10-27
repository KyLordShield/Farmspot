import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmspot_app/models/crop_category.dart';
import 'package:farmspot_app/screens/seller/add_crop_screen.dart';
import 'package:farmspot_app/widgets/seller_widgets.dart';

List<CropCategory> categories() => [
  CropCategory(
    id: 'LEAFVG',
    name: 'Vegetables',
    cropNames: ['tomato', 'tomatoes', 'kamatis'],
    description: 'Pechay, cabbage, carrots and tomatoes',
  ),
  CropCategory(
    id: 'FRUITS',
    name: 'Fruits',
    cropNames: ['apple', 'mango', 'mangga'],
  ),
  CropCategory(
    id: 'GRAINS',
    name: 'Rice, Corn & Grains',
    cropNames: ['corn', 'mais'],
  ),
  CropCategory(id: 'ROOTCP', name: 'Root Crops', cropNames: ['kamote']),
  CropCategory(
    id: 'HRBSPC',
    name: 'Herbs & Spices',
    cropNames: ['ginger', 'luya'],
  ),
  CropCategory(id: 'OTHERS', name: 'Other Crops'),
];

Finder cropField() => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.hintText == 'e.g. Cabbage, Kangkong, Tomatoes',
);
CropPickerTile tile(WidgetTester tester, String name) =>
    tester.widget<CropPickerTile>(
      find.byWidgetPredicate((w) => w is CropPickerTile && w.label == name),
    );

void main() {
  testWidgets('crop first suggests categories and allows manual corrections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddCropScreen(
          isFirstCrop: true,
          farmId: 'FARM01',
          loadCategories: () async => categories(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('CROP NAME')).dy,
      lessThan(tester.getTopLeft(find.text('CROP CATEGORY')).dy),
    );
    await tester.enterText(cropField(), ' KAMATIS! ');
    await tester.pump();
    expect(tile(tester, 'Vegetables').selected, isTrue);
    final other = find.byWidgetPredicate(
      (w) => w is CropPickerTile && w.label == 'Other Crops',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(other);
    await tester.pumpAndSettle();
    await tester.tap(other);
    await tester.pump();
    expect(tile(tester, 'Other Crops').selected, isTrue);
    await tester.scrollUntilVisible(
      cropField(),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(cropField(), 'Mangga');
    await tester.pump();
    expect(tile(tester, 'Fruits').selected, isTrue);
    await tester.enterText(cropField(), 'Unrecognized crop variety');
    await tester.pump();
    expect(tile(tester, 'Other Crops').selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a name typed while categories load is suggested after loading', (
    tester,
  ) async {
    final pending = Completer<List<CropCategory>>();
    await tester.pumpWidget(
      MaterialApp(
        home: AddCropScreen(
          isFirstCrop: true,
          farmId: 'FARM01',
          loadCategories: () => pending.future,
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(cropField(), 'tomatoes');
    pending.complete(categories());
    await tester.pumpAndSettle();
    expect(tile(tester, 'Vegetables').selected, isTrue);
  });

  test(
    'older category payloads still work and unknown crops are not guessed',
    () {
      final old = CropCategory.fromJson({
        'id': 'OLD001',
        'name': 'Legacy category',
      });
      expect(old.matchesCrop('tomato'), isFalse);
      expect(categories().first.matchesCrop('tomato sauce'), isTrue);
      expect(categories().first.matchesCrop(' TOMATOES! '), isTrue);
    },
  );
  testWidgets('category labels fit on a small phone with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(2),
          ),
          child: AddCropScreen(
            isFirstCrop: true,
            farmId: 'FARM01',
            loadCategories: () async => categories(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Rice, Corn & Grains'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Rice, Corn & Grains'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'marketing words and quantities preserve crop detection without substring or mixed matches',
    () {
      final all = categories();
      expect(CropCategory.suggestIndex(all, 'Apple fresh 50kg'), 1);
      expect(CropCategory.suggestIndex(all, 'Tomatoes Cheap For Sale'), 0);
      expect(CropCategory.suggestIndex(all, 'Pineapple fresh'), -1);
      expect(CropCategory.suggestIndex(all, 'Apple and tomatoes bundle'), -1);
    },
  );

  testWidgets('crop name and description stop oversized pasted text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddCropScreen(
          isFirstCrop: true,
          farmId: 'FARM01',
          loadCategories: () async => categories(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(cropField(), 'x' * 200);
    await tester.pump();
    expect(tester.widget<TextField>(cropField()).controller!.text.length, 40);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final description = find.byWidgetPredicate(
      (w) => w is TextField && w.maxLength == 1000,
    );
    await tester.scrollUntilVisible(
      description,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(description, 'd' * 1500);
    expect(tester.widget<TextField>(description).controller!.text.length, 1000);
  });
}
