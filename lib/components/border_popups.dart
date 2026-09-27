import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../services/border_crossing_service.dart';
import '../services/border_wait_service.dart';

/// Upright, non-interactive cards anchored to checkpoints, with collision culling.
class BorderPopups extends StatelessWidget {
  const BorderPopups({super.key, required this.entrances, required this.waits});
  final List<BorderEntrance> entrances;
  final BorderWaitService waits;

  @override
  Widget build(BuildContext context) {
    // Subscribe to camera changes so cards follow pan, zoom, rotation and pitch.
    final camera = MapCamera.of(context);
    if (camera.zoom < 15) return const SizedBox.shrink();
    // Smooth zoom weight: original size at overview zoom, up to 1.8× close up.
    final zoomWeight = ((camera.zoom - 11.5) / (19 - 11.5)).clamp(0.0, 1.0);
    final zoomScale = 1 + 0.8 * Curves.easeInOut.transform(zoomWeight);
    final controller = MapController.of(context);
    final points = entrances.map((e) => e.position).toList();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget place(List<Offset> offsets) {
            final occupied = <Rect>[];
            final children = <Widget>[];
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final baseWidth = 210.0 * scale;
            final baseHeight = 122.0 * scale;
            final width = baseWidth * zoomScale;
            final height = baseHeight * zoomScale;
            for (var i = 0; i < entrances.length; i++) {
              final anchor = offsets[i];
              if (!anchor.dx.isFinite || !anchor.dy.isFinite) continue;
              final rect = Rect.fromLTWH(
                anchor.dx - 0.5 * zoomScale,
                anchor.dy - height - 12 * zoomScale,
                width,
                height,
              );
              if (rect.left < 0 ||
                  rect.top < 0 ||
                  rect.right > constraints.maxWidth ||
                  rect.bottom > constraints.maxHeight ||
                  occupied.any((r) => r.overlaps(rect.inflate(6)))) {
                continue;
              }
              occupied.add(rect);
              children.add(
                Positioned.fromRect(
                  rect: rect,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    alignment: Alignment.bottomLeft,
                    child: SizedBox(
                      width: baseWidth,
                      height: baseHeight,
                      child: BorderPopup(
                        entrance: entrances[i],
                        wait: waits.reading(entrances[i]),
                      ),
                    ),
                  ),
                ),
              );
            }
            return Stack(children: children);
          }

          if (kIsWeb) return place(controller.toScreenLocationsSync(points));
          return FutureBuilder<List<Offset>>(
            future: controller.toScreenLocations(points),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.length != points.length) {
                return const SizedBox.shrink();
              }
              final ratio = defaultTargetPlatform == TargetPlatform.android
                  ? MediaQuery.devicePixelRatioOf(context)
                  : 1.0;
              return place(snapshot.data!.map((p) => p / ratio).toList());
            },
          );
        },
      ),
    );
  }
}

class BorderPopup extends StatelessWidget {
  const BorderPopup({
    super.key,
    required this.entrance,
    this.wait = const WaitReading('—'),
  });
  final BorderEntrance entrance;
  final WaitReading wait;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xF2182027),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            border: Border.all(color: const Color(0xFF46616F)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                entrance.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                entrance.direction,
                style: const TextStyle(
                  color: Color(0xFF71DDF4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                wait.label,
                style: const TextStyle(color: Color(0xFFBCC7CE), fontSize: 11),
              ),
              const SizedBox(height: 3),
              Text(
                wait.stale
                    ? 'Last known · refresh unavailable'
                    : wait.updated.isEmpty
                    ? 'Passenger wait'
                    : wait.updated,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF8E9DA6), fontSize: 9),
              ),
            ],
          ),
        ),
      ),
      Container(width: 1, height: 9, color: const Color(0xFF71DDF4)),
    ],
  );
}
