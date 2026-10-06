import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'farmspot_loader.dart';

/// Path to the brand loading animation. Drop your `.lottie` file here so
/// [FarmLottieLoading] lights up; until then it falls back to the CropRing
/// loader automatically.
const farmLottieAsset = 'assets/animations/Loading screen.lottie';

/// Full-screen loading layer over the app while an action runs, driven by the
/// brand Lottie animation. Cannot be dismissed by tapping outside or pressing
/// back. Close it later with
/// `Navigator.of(context, rootNavigator: true).pop()`.
void showFarmLottieLoading(BuildContext context, {String? message}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black45,
    builder: (_) => Center(
      child: FarmLottieLoading(message: message),
    ),
  );
}

/// Centered Lottie animation with a caption. If the animation asset is
/// missing or corrupt, it quietly falls back to the standard [FarmSpotLoader]
/// so a loading state can never be blank or crash.
class FarmLottieLoading extends StatelessWidget {
  final String? message;

  const FarmLottieLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Lottie.asset(
          farmLottieAsset,
          width: 280,
          height: 280,
          repeat: true,
          errorBuilder: (context, error, stackTrace) =>
              const FarmSpotLoader(size: 120),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(
            message!,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}