import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class MapOverlay extends StatelessWidget {
  const MapOverlay({
    super.key,
    this.text = 'One Moment Please...',
    this.edgeSoftness = 0.8,
  }) : assert(edgeSoftness >= 0);

  final String text;

  /// Edge feathering at the largest text size. Set to zero for sharp text.
  final double edgeSoftness;

  double get _fontSize {
    // Short messages stay large; longer text gradually shrinks to body size.
    final length = text.trim().replaceAll(RegExp(r'\s+'), ' ').runes.length;
    final progress = ((length - 40) / 200).clamp(0.0, 1.0);
    return 40 - (32 * progress);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.3, 1.0],
              colors: [
                Color.fromRGBO(0, 0, 0, 0.2), // 90% opacity black
                Color.fromRGBO(0, 0, 0, 0.5), // 30% opacity black
                Color.fromRGBO(0, 0, 0, 0.9), // 90% opacity black
              ],
            ),
          ),
        ),
        Positioned(
          left: 50,
          right: 50,
          bottom: 300,
          child: ImageFiltered(
            // Scale the feathering down for smaller paragraph text.
            imageFilter: ui.ImageFilter.blur(
              sigmaX: edgeSoftness * _fontSize / 56,
              sigmaY: edgeSoftness * _fontSize / 56,
            ),
            enabled: edgeSoftness > 0,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: _fontSize,
                height: 1.25,
                fontWeight: FontWeight.bold,
                fontFamily: 'Helvetica',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
