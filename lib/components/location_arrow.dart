import 'package:flutter/material.dart';

/// The bottom-center tip is anchored to the referenced map coordinate.
class LocationArrow extends StatelessWidget {
  const LocationArrow({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _ArrowPainter(color)));
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final arrow = Path()
      ..moveTo(size.width * 0.38, size.height * 0.12)
      ..lineTo(size.width * 0.62, size.height * 0.12)
      ..lineTo(size.width * 0.62, size.height * 0.55)
      ..lineTo(size.width * 0.86, size.height * 0.55)
      ..lineTo(size.width * 0.5, size.height)
      ..lineTo(size.width * 0.14, size.height * 0.55)
      ..lineTo(size.width * 0.38, size.height * 0.55)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(arrow, Paint()..color = color);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Color.lerp(color, Colors.white, 0.65)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => oldDelegate.color != color;
}
