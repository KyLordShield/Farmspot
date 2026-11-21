import 'package:flutter/material.dart';

class LoadingPulse extends StatefulWidget {
  const LoadingPulse({super.key, required this.child});

  final Widget child;

  @override
  State<LoadingPulse> createState() => _LoadingPulseState();
}

class _LoadingPulseState extends State<LoadingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    value: 1,
  );
  late final Animation<double> _opacity = _controller.drive(
    CurveTween(curve: Curves.easeInOut).chain(Tween(begin: .45, end: 1.0)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
