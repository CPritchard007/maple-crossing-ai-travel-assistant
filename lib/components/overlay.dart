import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/app_instance_service.dart';
import '../services/action_service.dart';

class MapOverlay extends StatelessWidget {
  const MapOverlay({
    super.key,
    this.text = '',
    this.edgeSoftness = 0.8,
    this.instanceService,
    this.actions,
  }) : assert(edgeSoftness >= 0);

  final ActionService? actions;
  final String text;
  final AppInstanceService? instanceService;

  /// Edge feathering at the largest text size. Set to zero for sharp text.
  final double edgeSoftness;

  double _fontSize(String text) {
    // Short messages stay large; longer text gradually shrinks to body size.
    final length = text.trim().replaceAll(RegExp(r'\s+'), ' ').runes.length;
    final progress = ((length - 40) / 200).clamp(0.0, 1.0);
    return 40 - (32 * progress);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: (actions ?? actionService).overlayText,
      builder: (context, currentText, _) =>
          _buildOverlay(context, currentText ?? text),
    );
  }

  Widget _buildOverlay(BuildContext context, String displayText) {
    final fontSize = _fontSize(displayText);
    return Stack(
      children: [
        IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.3, 1.0],
                colors: [
                  Color.fromRGBO(0, 0, 0, 0.0), // 40% opacity black
                  Color.fromRGBO(0, 0, 0, 0.0), // 30% opacity black
                  Color.fromRGBO(0, 0, 0, 0.0), // 90% opacity black
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: ListenableBuilder(
              listenable: instanceService ?? appInstance,
              builder: (context, _) {
                final status = (instanceService ?? appInstance).status;
                return Row(
                  children: [
                    IconButton(
                      tooltip: 'Open menu',
                      icon: const Icon(
                        Icons.menu,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        switch (status) {
                          AppInstanceStatus.initializing => 'Initializing',
                          AppInstanceStatus.ready => 'Connected',
                          AppInstanceStatus.failed => 'Connection unavailable',
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: status == AppInstanceStatus.ready
                              ? Colors.green
                              : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    if (status == AppInstanceStatus.initializing) ...[
                      const SizedBox(width: 10),
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                          semanticsLabel: 'Initializing',
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 50,
          right: 50,
          bottom: 300,
          child: IgnorePointer(
            child: ImageFiltered(
              // Scale the feathering down for smaller paragraph text.
              imageFilter: ui.ImageFilter.blur(
                sigmaX: edgeSoftness * fontSize / 56,
                sigmaY: edgeSoftness * fontSize / 56,
              ),
              enabled: edgeSoftness > 0,
              child: Text(
                displayText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  height: 1.25,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Helvetica',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
