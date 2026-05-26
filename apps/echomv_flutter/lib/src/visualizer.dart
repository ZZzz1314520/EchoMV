import 'dart:math' as math;

import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    super.key,
    required this.isPlaying,
    this.peaks,
  });

  final bool isPlaying;
  final List<double>? peaks;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _VisualizerPainter(
            progress: _controller.value,
            isPlaying: widget.isPlaying,
            peaks: widget.peaks,
            color: Theme.of(context).colorScheme.primary,
            accent: Theme.of(context).colorScheme.tertiary,
          ),
          size: const Size.square(220),
        );
      },
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  const _VisualizerPainter({
    required this.progress,
    required this.isPlaying,
    required this.peaks,
    required this.color,
    required this.accent,
  });

  final double progress;
  final bool isPlaying;
  final List<double>? peaks;
  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.34;
    final values = peaks?.isNotEmpty == true
        ? peaks!
        : List<double>.generate(36, (i) => 0.35 + math.sin(i * 0.7) * 0.24);
    final count = math.max(36, values.length * 3);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.14);
    canvas.drawCircle(center, radius, ringPaint);

    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2 + progress * math.pi * 2;
      final peak = values[i % values.length];
      final pulse = isPlaying ? (0.75 + 0.25 * math.sin(progress * 8 + i)) : 0.35;
      final length = 12 + peak * 34 * pulse;
      final start = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final end = Offset(
        center.dx + math.cos(angle) * (radius + length),
        center.dy + math.sin(angle) * (radius + length),
      );
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2
        ..color = Color.lerp(color, accent, i / count)!.withValues(alpha: 0.82);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        isPlaying != oldDelegate.isPlaying ||
        peaks != oldDelegate.peaks;
  }
}
