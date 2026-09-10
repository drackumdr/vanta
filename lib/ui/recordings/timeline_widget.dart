import 'package:flutter/material.dart';

import '../../models/recording_models.dart';
import '../../services/hikvision_service.dart';

/// Línea de tiempo de 24h con bloques de grabación; tap para reproducir.
class TimelineWidget extends StatelessWidget {
  const TimelineWidget({
    super.key,
    required this.segments,
    required this.offset,
    required this.onSegmentTap,
  });

  final List<RecordingSegment> segments;
  final Duration offset;
  final ValueChanged<RecordingSegment> onSegmentTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final localDx = details.localPosition.dx;
            final fraction = (localDx / width).clamp(0.0, 1.0);
            final seconds = fraction * const Duration(hours: 24).inSeconds;

            RecordingSegment? best;
            for (final seg in segments) {
              final start =
                  HikvisionService.toDeviceLocal(seg.startUtc, offset);
              final end = HikvisionService.toDeviceLocal(seg.endUtc, offset);
              final segStart =
                  Duration(hours: start.hour, minutes: start.minute, seconds: start.second)
                      .inSeconds;
              final segEnd =
                  Duration(hours: end.hour, minutes: end.minute, seconds: end.second)
                      .inSeconds;
              if (seconds >= segStart && seconds <= segEnd) {
                best = seg;
                break;
              }
            }
            if (best != null) onSegmentTap(best);
          },
          child: CustomPaint(
            size: Size(width, height),
            painter: _TimelinePainter(segments: segments, offset: offset),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.segments, required this.offset});

  final List<RecordingSegment> segments;
  final Duration offset;

  static const _bg = Color(0xFF0B0C0F);
  static const _grid = Color(0xFF1F232B);
  static const _timing = Color(0xFF2F9BFF);
  static const _event = Color(0xFF8A5BF2);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = _bg);

    // Líneas horarias
    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var h = 1; h < 24; h++) {
      final x = size.width * h / 24;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Bloques de grabación
    final block = Paint();
    for (final seg in segments) {
      final start = HikvisionService.toDeviceLocal(seg.startUtc, offset);
      final end = HikvisionService.toDeviceLocal(seg.endUtc, offset);
      final startSec = Duration(
              hours: start.hour, minutes: start.minute, seconds: start.second)
          .inSeconds;
      var endSec = Duration(hours: end.hour, minutes: end.minute, seconds: end.second)
          .inSeconds;
      if (endSec < startSec) endSec = const Duration(hours: 24).inSeconds;
      final x0 = size.width * startSec / const Duration(hours: 24).inSeconds;
      final x1 = size.width * (endSec - startSec).clamp(0, const Duration(hours: 24).inSeconds) /
          const Duration(hours: 24).inSeconds;
      if (x1 <= 0) continue;
      block.color = seg.isTiming ? _timing : _event;
      final rRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x0, size.height * 0.28, x1, size.height * 0.44),
        const Radius.circular(3),
      );
      canvas.drawRRect(rRect, block);
    }

    // Marcas 00:00 / 12:00 / 24:00
    _drawLabel(canvas, '00:00', 4, size);
    _drawLabel(canvas, '12:00', size.width / 2, size);
    _drawLabel(canvas, '24:00', size.width - 4, size, alignRight: true);
  }

  void _drawLabel(Canvas canvas, String text, double x, Size size,
      {bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white30, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? x - tp.width : x;
    tp.paint(canvas, Offset(dx, size.height - tp.height));
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.offset != offset;
}