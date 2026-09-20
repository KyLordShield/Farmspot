import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// FarmSpot brand splash: the logo pops in with a gentle spring while the
/// tagline fades below it and a green progress bar fills across the bottom.
/// AuthGate shows this while the startup token check runs, so the animation
/// duration matches the minimum splash time.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _logoScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 0.85, curve: Curves.easeIn),
    );
    _controller.forward();
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
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            FadeTransition(
              opacity: _logoOpacity,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.5, end: 1.0).animate(_logoScale),
                child: const FarmSpotLogo(size: 170),
              ),
            ),
            const SizedBox(height: 18),
            FadeTransition(
              opacity: _taglineOpacity,
              child: const Text(
                'A healthy Connection',
                style: TextStyle(
                  color: AppColors.primaryGreen,
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(flex: 3),
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 48, 40),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _controller.value,
                    minHeight: 6,
                    backgroundColor:
                        AppColors.primaryGreen.withValues(alpha: 0.12),
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.primaryGreen),
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