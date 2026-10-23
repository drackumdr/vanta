import 'package:flutter_test/flutter_test.dart';
import 'package:vanta/models/recording_models.dart';
import 'package:vanta/services/hikvision_service.dart';

void main() {
  group('HikvisionService.parseHikvisionTime', () {
    test('parses timestamp with trailing Z as device local clock time', () {
      final dt = HikvisionService.parseHikvisionTime('2026-09-11T07:06:57Z');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 9);
      expect(dt.day, 11);
      expect(dt.hour, 7);
      expect(dt.minute, 6);
      expect(dt.second, 57);
    });

    test('parses timestamp with timezone offset preserving clock time', () {
      final dt = HikvisionService.parseHikvisionTime('2026-09-11T10:42:06-06:00');
      expect(dt, isNotNull);
      expect(dt!.hour, 10);
      expect(dt.minute, 42);
      expect(dt.second, 6);
    });

    test('returns null for empty string', () {
      expect(HikvisionService.parseHikvisionTime(''), isNull);
    });
  });

  group('RecordingSegment & Midnight Boundaries', () {
    test('segment crossing midnight from yesterday matches start of today', () {
      final seg = RecordingSegment(
        trackId: '101',
        startLocal: DateTime(2026, 9, 10, 23, 54, 35),
        endLocal: DateTime(2026, 9, 11, 1, 39, 56),
        contentType: 'video',
      );

      final todayStart = DateTime(2026, 9, 11);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Visible window on today
      final visibleStart = seg.startLocal.isBefore(todayStart) ? todayStart : seg.startLocal;
      final visibleEnd = seg.endLocal.isAfter(todayEnd) ? todayEnd : seg.endLocal;

      final startSec = visibleStart.difference(todayStart).inSeconds.toDouble();
      final endSec = visibleEnd.difference(todayStart).inSeconds.toDouble();

      expect(startSec, 0.0);
      expect(endSec, 3600 + 39 * 60 + 56); // 5996.0

      // Target at 00:00:00 matches segment
      final target = DateTime(2026, 9, 11, 0, 0, 0);
      final matches = (target.isAfter(seg.startLocal) || target.isAtSameMomentAs(seg.startLocal)) &&
          target.isBefore(seg.endLocal);
      expect(matches, isTrue);
    });

    test('active ongoing segment matches current time within segment', () {
      final seg = RecordingSegment(
        trackId: '101',
        startLocal: DateTime(2026, 9, 11, 10, 42, 6),
        endLocal: DateTime(2026, 9, 11, 10, 57, 53),
        name: 'recordType.meta.hikvision.com/timing',
      );

      expect(seg.isTiming, isTrue);

      final target = DateTime(2026, 9, 11, 10, 50, 0);
      final matches = (target.isAfter(seg.startLocal) || target.isAtSameMomentAs(seg.startLocal)) &&
          target.isBefore(seg.endLocal);
      expect(matches, isTrue);
    });
  });
}
