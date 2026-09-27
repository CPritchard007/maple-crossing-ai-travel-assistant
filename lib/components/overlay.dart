import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../services/app_instance_service.dart';
import '../services/action_service.dart';
import '../services/tts_service.dart';

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

  /// Text edge feathering. Set to zero for sharp text.
  final double edgeSoftness;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: (actions ?? actionService).overlayText,
      builder: (context, currentText, _) =>
          _buildOverlay(context, currentText ?? text),
    );
  }

  Widget _buildOverlay(BuildContext context, String displayText) {
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
        if (displayText.isNotEmpty)
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.sizeOf(context).height * 0.15,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SizedBox(
                  height: 140,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: edgeSoftness * 24 / 56,
                      sigmaY: edgeSoftness * 24 / 56,
                    ),
                    enabled: edgeSoftness > 0,
                    child: NarrationText(
                      text: displayText,
                      progress: ttsService.playbackProgress,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Scrolls long narration using audio playback progress, with manual scrolling.
class NarrationText extends StatefulWidget {
  const NarrationText({super.key, required this.text, required this.progress});

  final String text;
  final ValueListenable<double> progress;

  @override
  State<NarrationText> createState() => _NarrationTextState();
}

class _NarrationTextState extends State<NarrationText> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_followPlayback);
  }

  @override
  void didUpdateWidget(NarrationText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_followPlayback);
      widget.progress.addListener(_followPlayback);
    }
    if (oldWidget.text != widget.text && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  void _followPlayback() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // Keep the approximate spoken line near the middle of the viewport.
    final target =
        ((position.maxScrollExtent + position.viewportDimension) *
                    widget.progress.value -
                position.viewportDimension / 2)
            .clamp(0.0, position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.linear,
    );
  }

  @override
  void dispose() {
    widget.progress.removeListener(_followPlayback);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    child: Text(
      widget.text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        height: 1.4,
        fontWeight: FontWeight.bold,
        fontFamily: 'Helvetica',
        shadows: [Shadow(color: Colors.black, blurRadius: 6)],
      ),
    ),
  );
}
