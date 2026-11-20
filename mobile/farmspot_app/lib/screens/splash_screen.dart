import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../widgets/common_widgets.dart';

/// Shows a looping animation while the app restores its local session.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Lottie.asset(
          'assets/animations/Farmers.lottie',
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (context, error, stackTrace) =>
              const Center(child: FarmSpotLogo(size: 170)),
        ),
      ),
    );
  }
}
