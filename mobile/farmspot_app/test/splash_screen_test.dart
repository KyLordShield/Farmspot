import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:farmspot_app/screens/splash_screen.dart';

LottieComposition intro() => LottieComposition.parseJsonBytes(
  utf8.encode(
    '{"v":"5.7.4","fr":30,"ip":0,"op":60,"w":100,"h":100,"layers":[]}',
  ),
);

class _PendingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Completer<ByteData>().future;
}

Widget app(VoidCallback finished) => DefaultAssetBundle(
  bundle: _PendingBundle(),
  child: MaterialApp(home: SplashScreen(onFinished: finished)),
);

void main() {
  testWidgets('intro keeps full playback with disabled system animations', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var completed = 0;
    await tester.pumpWidget(app(() => completed++));
    final lottie = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
    lottie.onLoaded!(intro());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(completed, 0);
    expect(lottie.controller!.value, lessThan(0.5));
    await tester.pump(const Duration(seconds: 2));
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background time does not skip the intro on resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var completed = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(app(() => completed++));
    final lottie = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
    lottie.onLoaded!(intro());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final progress = lottie.controller!.value;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 15));
    expect(completed, 0);
    expect(lottie.controller!.value, progress);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(completed, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an asset that never loads releases startup after the timeout', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var completed = 0;
    await tester.pumpWidget(app(() => completed++));
    await tester.pump(const Duration(seconds: 13));
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
