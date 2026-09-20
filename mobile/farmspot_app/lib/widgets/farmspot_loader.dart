import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Branded FarmSpot loading indicator.
///
/// - Use the default size (or bigger) for screen-level loading states: the
///   logo sits inside a rotating crop ring with expanding soil ripples.
/// - Use a small size (under 56px) for tight inline spots; it collapses to a
///   compact row of bouncing seeds so it still feels on-brand inside forms
///   and image placeholders.
class FarmSpotLoader extends StatefulWidget {
  final double size;
  final String? message;

  const FarmSpotLoader({super.key, this.size = 96, this.message});

  @override
  State<FarmSpotLoader> createState() => _FarmSpotLoaderState();
}

class _FarmSpotLoaderState extends State<FarmSpotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.size < 56;
    return Center(
      child: compact ? _buildCompact() : _buildFull(),
    );
  }

  Widget _buildFull() {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(size),
                    painter: _RipplePainter(progress: t),
                  ),
                  SizedBox(
                    width: size,
                    height: size,
                    child: CustomPaint(
                      painter: _CropRingPainter(progress: t),
                    ),
                  ),
                  Transform.scale(
                    scale: 1 + 0.04 * math.sin(t * 4 * math.pi),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: size * 0.58,
                      height: size * 0.58,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SeedDots(progress: t, width: size * 0.55),
            if (widget.message != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.message!,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCompact() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.size < 40
          ? SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _CropRingPainter(progress: _controller.value),
              ),
            )
          : _SeedDots(progress: _controller.value, width: widget.size),
    );
  }
}

/// Three bouncing seeds that suggest growth in a field after watering.
class _SeedDots extends StatelessWidget {
  final double progress;
  final double width;

  const _SeedDots({required this.progress, required this.width});

  @override
  Widget build(BuildContext context) {
    final dotSize = (width / 5).clamp(5.0, 12.0);
    const colors = [
      AppColors.primaryGreen,
      AppColors.lightGreen,
      AppColors.mutedGreen,
    ];
    final t = progress;

    return SizedBox(
      height: dotSize * 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(3, (i) {
          final phase = (t + i * 0.28) % 1.0;
          final lift = math.sin(phase * 2 * math.pi) * -dotSize * 0.7;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: dotSize * 0.45),
            child: Transform.translate(
              offset: Offset(0, lift),
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors[i],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Expanding staggered circles around the logo, like soil ripples from rain.
class _RipplePainter extends CustomPainter {
  final double progress;

  const _RipplePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final phase = (progress + i * 0.5) % 1.0;
      final radius = size.shortestSide / 2 * (0.28 + 0.55 * phase);
      final paint = Paint()
        ..color = AppColors.lightGreen.withValues(alpha: (1 - phase) * 0.35);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.progress != progress;
}

/// A thin static track plus a rotating comet arc around the logo — the "crop
/// rotation" ring that marks FarmSpot's farmer identity.
class _CropRingPainter extends CustomPainter {
  final double progress;

  const _CropRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primaryGreen.withValues(alpha: 0.15);
    canvas.drawCircle(rect.center, size.shortestSide / 2 - 2, track);

    final start = progress * 2 * math.pi * 3;
    final trail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = AppColors.lightGreen;
    canvas.drawArc(
      rect.deflate(4),
      start - math.pi * 0.55,
      math.pi * 0.55,
      false,
      trail,
    );

    final accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..color = AppColors.primaryGreen;
    canvas.drawArc(
      rect.deflate(4),
      start,
      math.pi * 1.25,
      false,
      accent,
    );
  }

  @override
  bool shouldRepaint(_CropRingPainter old) => old.progress != progress;
}

/// Full-screen loading layer over the app while an action runs. It cannot be
/// dismissed by tapping outside or pressing back. Close it later with
/// `Navigator.of(context, rootNavigator: true).pop()`.
void showFarmSpotLoading(BuildContext context, {String? message}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black45,
    builder: (_) => Center(
      child: FarmSpotLoader(message: message),
    ),
  );
}