import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';

/// FarmSpot brand splash: a single smooth logo moment — fade in, hold, fade
/// out — on a white background. No progress bar, no springy pop. [onFinished]
/// fires once the fade-out completes so the caller can swap screens exactly
/// when the logo has had its moment — no fixed timer to race against.
class SplashScreen extends StatefulWidget {
  final VoidCallback? onFinished;

  const SplashScreen({super.key, this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    // 28% fade in, 50% hold, 22% fade out — one gentle brand moment.
    _logoOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 28,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 22,
      ),
    ]).animate(_controller);
    _controller.forward().whenComplete(() {
      if (mounted) widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _logoOpacity,
          child: const FarmSpotLogo(size: 170),
        ),
      ),
    );
  }
}