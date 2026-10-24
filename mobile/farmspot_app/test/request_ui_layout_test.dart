import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:farmspot_app/models/buy_request.dart';
import 'package:farmspot_app/screens/premium/my_requests_screen.dart';
import 'package:farmspot_app/screens/seller/requests_board_screen.dart';
import 'package:farmspot_app/theme.dart';
import 'buy_requests_test.dart' show FakeRequests;

const cabbage = BuyRequest(
  id: 'REQ001',
  crop: 'Cabbage',
  quantityKg: 20,
  frequency: 'weekly',
  buyerName: 'Maraag Kitchen',
  buyerPhone: '09171234567',
  pickupLocation: 'Can collect in Sudlon on Monday mornings.',
  note:
      'Fresh heads for our weekly kitchen supply. Please message your price and availability.',
  latitude: 10.3796,
  longitude: 123.7847,
  distanceKm: 3.2,
  responseCount: 3,
);
const pechay = BuyRequest(
  id: 'REQ002',
  crop: 'Pechay',
  quantityKg: 10,
  frequency: 'one-time',
  buyerName: 'Cebu Corner Eatery',
);
const captureKey = Key('request-ui-capture');

void main() {
  setUpAll(() async {
    final dir = Platform.environment['FARMSPOT_PREVIEW_FONTS'];
    if (dir == null) return;
    final roboto = FontLoader('Roboto');
    for (final name in [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-black.ttf',
    ]) {
      roboto.addFont(
        File('$dir/$name').readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await roboto.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '$dir/materialicons-regular.otf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    await icons.load();
  });
  setUp(
    () => SharedPreferences.setMockInitialValues({'auth_token': 'test-token'}),
  );

  Future<void> showPage(
    WidgetTester tester,
    Widget page, {
    double width = 390,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final dir = Platform.environment['FARMSPOT_UI_PREVIEW_DIR'];
    if (dir == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(dir).create(recursive: true);
      await File('$dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('buyer requests keep posting and message controls clear', (
    tester,
  ) async {
    await showPage(
      tester,
      MyRequestsScreen(gateway: FakeRequests()..rows = [cabbage, pechay]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('New request'), findsOneWidget);
    expect(find.text('View seller messages (3)'), findsOneWidget);
    await capture(tester, 'buyer-requests');
  });

  testWidgets('seller board presents crop, map, and contact actions clearly', (
    tester,
  ) async {
    await showPage(
      tester,
      RequestsBoardScreen(gateway: FakeRequests()..rows = [cabbage, pechay]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('View map pin'), findsOneWidget);
    await capture(tester, 'seller-request-board');
  });

  testWidgets('buyer cards fit a narrow phone with larger text', (
    tester,
  ) async {
    await showPage(
      tester,
      MyRequestsScreen(gateway: FakeRequests()..rows = [cabbage]),
      width: 320,
      scale: 1.3,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('New request'), findsOneWidget);
  });

  testWidgets('seller contact actions remain usable with larger text', (
    tester,
  ) async {
    await showPage(
      tester,
      RequestsBoardScreen(gateway: FakeRequests()..rows = [cabbage]),
      width: 320,
      scale: 1.3,
    );
    await tester.ensureVisible(find.text('Call buyer'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Message buyer'), findsOneWidget);
    expect(find.text('Call buyer'), findsOneWidget);
  });
}
