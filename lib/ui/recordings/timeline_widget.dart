import 'package:flutter/material.dart';

import '../../models/recording_models.dart';

/// Datos de una pista de grabación en la línea de tiempo para una cámara.
class TimelineTrack {
  final String id;
  final String label;
  final Color color;
  final List<RecordingSegment> segments;

  const TimelineTrack({
    required this.id,
    required this.label,
    required this.color,
    required this.segments,
  });
}

/// Línea de tiempo interactiva de 24 horas con soporte multipista y cabezal arrastrable.
class TimelineWidget extends StatefulWidget {
  const TimelineWidget({
    super.key,
    required this.tracks,
    required this.selectedDay,
    required this.currentSeconds,
    required this.onSeek,
    this.onScrubbing,
  });

  final List<TimelineTrack> tracks;
  final DateTime selectedDay;
  final double currentSeconds; // Segundos desde medianoche (0 .. 86400)
  final ValueChanged<double> onSeek;
  final ValueChanged<double>? onScrubbing;

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> {
  double? _dragSeconds;

  double _calcSeconds(double dx, double width) {
    final frac = (dx / width).clamp(0.0, 1.0);
    return frac * 86400.0;
  }

  @override
  Widget build(BuildContext context) {
    final activeSeconds = (_dragSeconds ?? widget.currentSeconds).clamp(0.0, 86400.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final sec = _calcSeconds(details.localPosition.dx, width);
            setState(() => _dragSeconds = sec);
            widget.onScrubbing?.call(sec);
            widget.onSeek(sec);
          },
          onPanStart: (details) {
            final sec = _calcSeconds(details.localPosition.dx, width);
            setState(() => _dragSeconds = sec);
            widget.onScrubbing?.call(sec);
          },
          onPanUpdate: (details) {
            final sec = _calcSeconds(details.localPosition.dx, width);
            setState(() => _dragSeconds = sec);
            widget.onScrubbing?.call(sec);
          },
          onPanEnd: (details) {
            final sec = _dragSeconds ?? widget.currentSeconds;
            setState(() => _dragSeconds = null);
            widget.onSeek(sec);
          },
          onPanCancel: () {
            setState(() => _dragSeconds = null);
          },
          child: CustomPaint(
            size: Size(width, height),
            painter: _TimelinePainter(
              tracks: widget.tracks,
              selectedDay: widget.selectedDay,
              currentSeconds: activeSeconds,
              isDragging: _dragSeconds != null,
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.tracks,
    required this.selectedDay,
    required this.currentSeconds,
    required this.isDragging,
  });

  final List<TimelineTrack> tracks;
  final DateTime selectedDay;
  final double currentSeconds;
  final bool isDragging;

  static const _bg = Color(0xFF0D0E12);
  static const _laneBg = Color(0xFF14171E);
  static const _laneAltBg = Color(0xFF101217);
  static const _gridColor = Color(0xFF222630);
  static const _needleColor = Color(0xFF00E5FF);
  static const _eventColor = Color(0xFFFF7043);

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Fondo general
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    // Altura de la regla superior para horas
    const rulerHeight = 22.0;
    final tracksHeight = height - rulerHeight;
    final trackCount = tracks.isEmpty ? 1 : tracks.length;
    final laneHeight = tracksHeight / trackCount;

    final dayStart = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // 1. Dibujar carriles de cada pista
    for (var i = 0; i < trackCount; i++) {
      final y = rulerHeight + i * laneHeight;
      final lanePaint = Paint()..color = (i % 2 == 0) ? _laneBg : _laneAltBg;
      canvas.drawRect(Rect.fromLTWH(0, y, width, laneHeight), lanePaint);

      // Línea divisoria inferior de carril
      canvas.drawLine(
        Offset(0, y + laneHeight),
        Offset(width, y + laneHeight),
        Paint()..color = _gridColor..strokeWidth = 1,
      );

      // Etiquetas y segmentos si existen pistas
      if (i < tracks.length) {
        final track = tracks[i];

        // Segmentos
        final blockPaint = Paint();
        for (final seg in track.segments) {
          if (seg.endLocal.isBefore(dayStart) || seg.startLocal.isAfter(dayEnd)) {
            continue;
          }
          final visibleStart =
              seg.startLocal.isBefore(dayStart) ? dayStart : seg.startLocal;
          final visibleEnd =
              seg.endLocal.isAfter(dayEnd) ? dayEnd : seg.endLocal;

          final startSec = visibleStart.difference(dayStart).inSeconds.toDouble();
          final endSec = visibleEnd.difference(dayStart).inSeconds.toDouble();

          final x0 = width * (startSec / 86400.0);
          final x1 = width * ((endSec - startSec).clamp(0.0, 86400.0) / 86400.0);
          if (x1 <= 0) continue;

          blockPaint.color = seg.isTiming ? track.color : _eventColor;
          final segRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x0,
              y + (laneHeight * 0.20),
              x1.clamp(2.0, width),
              laneHeight * 0.60,
            ),
            const Radius.circular(2.5),
          );
          canvas.drawRRect(segRect, blockPaint);
        }

        // Nombre / insignia de la cámara en el borde izquierdo
        _drawTrackBadge(canvas, track, y, laneHeight);
      }
    }

    // 2. Líneas horarias y regla de tiempo
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    final halfGridPaint = Paint()
      ..color = const Color(0xFF181B22)
      ..strokeWidth = 1;

    for (var h = 0; h <= 24; h++) {
      final x = width * (h / 24.0);

      // Línea vertical completa
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);

      // Marcador de hora en la regla (cada 2 horas)
      if (h % 2 == 0) {
        final label = '${h.toString().padLeft(2, '0')}:00';
        _drawRulerLabel(canvas, label, x, width);
      }
    }

    // Líneas intermedias de media hora
    for (var h = 0; h < 24; h++) {
      final x = width * ((h + 0.5) / 24.0);
      canvas.drawLine(Offset(x, rulerHeight), Offset(x, height), halfGridPaint);
    }

    // 3. Cabezal / Aguja de reproducción (Playhead)
    final needleX = width * (currentSeconds / 86400.0);

    // Línea vertical de la aguja
    final needlePaint = Paint()
      ..color = _needleColor
      ..strokeWidth = isDragging ? 2.5 : 1.5;
    canvas.drawLine(Offset(needleX, rulerHeight), Offset(needleX, height), needlePaint);

    // Triángulo superior e indicador flotante de tiempo
    _drawPlayheadCursor(canvas, needleX, currentSeconds, width);
  }

  void _drawTrackBadge(Canvas canvas, TimelineTrack track, double y, double laneHeight) {
    final badgePaint = Paint()
      ..color = track.color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = track.color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const badgeX = 8.0;
    final badgeY = y + (laneHeight - 16.0) / 2;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeX, badgeY, 56, 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(badgeRect, badgePaint);
    canvas.drawRRect(badgeRect, borderPaint);

    final tp = TextPainter(
      text: TextSpan(
        text: track.label,
        style: TextStyle(
          color: track.color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 52);
    tp.paint(canvas, Offset(badgeX + 4, badgeY + 2));
  }

  void _drawRulerLabel(Canvas canvas, String text, double x, double totalWidth) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    var dx = x - (tp.width / 2);
    if (dx < 4) dx = 4;
    if (dx + tp.width > totalWidth - 4) dx = totalWidth - tp.width - 4;

    tp.paint(canvas, Offset(dx, 4));
  }

  void _drawPlayheadCursor(Canvas canvas, double x, double seconds, double totalWidth) {
    // Triángulo invertido del cabezal
    final triPath = Path()
      ..moveTo(x - 5, 14)
      ..lineTo(x + 5, 14)
      ..lineTo(x, 22)
      ..close();
    canvas.drawPath(triPath, Paint()..color = _needleColor);

    // Formato HH:mm:ss
    final totalSec = seconds.toInt();
    final h = (totalSec ~/ 3600) % 24;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    final timeStr =
        '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';

    final badgeTp = TextPainter(
      text: TextSpan(
        text: timeStr,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final badgeWidth = badgeTp.width + 8;
    const badgeHeight = 14.0;
    var badgeX = x - (badgeWidth / 2);
    if (badgeX < 2) badgeX = 2;
    if (badgeX + badgeWidth > totalWidth - 2) badgeX = totalWidth - badgeWidth - 2;

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeX, 0, badgeWidth, badgeHeight),
      const Radius.circular(3),
    );
    canvas.drawRRect(badgeRect, Paint()..color = _needleColor);
    badgeTp.paint(canvas, Offset(badgeX + 4, 1));
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.tracks != tracks ||
      oldDelegate.selectedDay != selectedDay ||
      oldDelegate.currentSeconds != currentSeconds ||
      oldDelegate.isDragging != isDragging;
}
