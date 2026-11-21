import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../widgets/common_widgets.dart';

/// Plays the intro once while the app restores its local session.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        animationBehavior: AnimationBehavior.preserve,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
  Timer? _loadTimeout;
  bool _finished = false;
  bool _loaded = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A missing or unreadable asset must not block sign-in indefinitely.
    _loadTimeout = Timer(const Duration(seconds: 12), _finish);
  }

  void _finish() {
    if (!mounted || _finished) return;
    _finished = true;
    _loadTimeout?.cancel();
    widget.onFinished?.call();
  }

  void _onLoaded(LottieComposition composition) {
    if (_loaded || _finished) return;
    _loaded = true;
    _loadTimeout?.cancel();
    _controller.duration = composition.duration;
    if (_active) _controller.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _controller.stop(canceled: false);
    } else if (_loaded && !_finished) {
      _controller.forward();
    }
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: Transform.scale(
                scale: 1.5,
                child: Lottie.asset(
                  'assets/animations/Farmers.lottie',
                  controller: _controller,
                  onLoaded: _onLoaded,
                  fit: BoxFit.contain,
                  repeat: false,
                  errorBuilder: (context, error, stackTrace) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _finish(),
                    );
                    return const Center(child: FarmSpotLogo(size: 170));
                  },
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: const Alignment(0, .52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Semantics(
                    label: 'FarmSpot',
                    child: ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (
                                var index = 0;
                                index < 'FarmSpot'.length;
                                index++
                              )
                                Transform.translate(
                                  offset: Offset(
                                    0,
                                    -14 *
                                        math.sin(
                                          math.pi *
                                              Curves.easeInOut.transform(
                                                ((_controller.value -
                                                            .08 -
                                                            index * .035) /
                                                        .12)
                                                    .clamp(0.0, 1.0),
                                              ),
                                        ),
                                  ),
                                  child: Text(
                                    'FarmSpot'[index],
                                    style: TextStyle(
                                      fontFamily: 'Cooper',
                                      fontSize: 40,
                                      letterSpacing: .2,
                                      // Colors sampled from Farmers.lottie.
                                      color: index < 4
                                          ? const Color(0xFF00664E)
                                          : const Color(0xFFFC744F),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
