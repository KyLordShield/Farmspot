import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../widgets/common_widgets.dart';

/// Path to the brand startup animation.
const farmspotIntroAsset = 'assets/animations/Farmspot Intro Lottie.lottie';

/// FarmSpot startup intro: the brand Lottie animation plays exactly once on a
/// white background. When it reaches its final frame it holds there — the last
/// frame is left frozen on screen rather than looping or fading out — so the
/// caller can keep it up for as long as bootstrapping takes and swap screens the
/// instant both are ready. [onFinished] fires when the animation completes (or,
/// if the asset is missing or corrupt, right after the fallback paints) so the
/// gate can never be stranded on a permanent splash.
class SplashScreen extends StatefulWidget {
  final VoidCallback? onFinished;

  const SplashScreen({super.key, this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _finished = false;
  bool _loaded = false;
  bool _playScheduled = false;
  Timer? _loadTimeout;

  @override
  void initState() {
    super.initState();
    // No duration yet: it is taken from the loaded composition so the intro
    // always runs its true length, whatever the asset happens to be.
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      // This one-shot brand intro must keep its authored timing even when
      // Android reports disabled system animations during startup.
      animationBehavior: AnimationBehavior.preserve,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    // Bound asset loading, rather than cutting into the playback duration.
    _loadTimeout = Timer(const Duration(seconds: 12), _finish);
  }

  void _onLoaded(LottieComposition composition) {
    if (_finished || _loaded) return;
    _loaded = true;
    _loadTimeout?.cancel();
    _controller.duration = composition.duration;
    _schedulePlayback();
  }

  void _schedulePlayback() {
    if (!_loaded || _finished || _playScheduled) return;
    _playScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playScheduled = false;
      if (!mounted || _finished) return;
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) return;
      _controller.forward();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedulePlayback();
    } else {
      _controller.stop(canceled: false);
    }
  }

  /// Fires [onFinished] once, letting the animation's final frame stay put in
  /// the meantime (the gate only swaps the screen once it is also bootstrapped).
  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    _loadTimeout?.cancel();
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadTimeout?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Lottie.asset(
          farmspotIntroAsset,
          controller: _controller,
          fit: BoxFit.contain,
          onLoaded: _onLoaded,
          errorBuilder: (context, error, stackTrace) {
            // The asset failed to load, so no completion will ever arrive.
            // Paint the logo as a fallback and release the gate on the next
            // frame instead of leaving a blank white screen.
            WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
            return const Center(child: FarmSpotLogo(size: 170));
          },
        ),
      ),
    );
  }
}
