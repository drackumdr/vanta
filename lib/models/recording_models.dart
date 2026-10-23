import 'package:flutter/foundation.dart';

@immutable
class RecordingSegment {
  final String trackId;
  final DateTime startLocal;
  final DateTime endLocal;
  final String? contentType;
  final String? codecType;
  final String? playbackUri;
  final String? name;

  const RecordingSegment({
    required this.trackId,
    required this.startLocal,
    required this.endLocal,
    this.contentType,
    this.codecType,
    this.playbackUri,
    this.name,
  });

  /// Alias de compatibilidad
  DateTime get startUtc => startLocal;
  DateTime get endUtc => endLocal;

  bool get isTiming =>
      (contentType != null && contentType!.toLowerCase().contains('timing')) ||
      (name != null &&
          (name!.toLowerCase().contains('timing') ||
              name!.toLowerCase().contains('schedule')));

  Duration get duration => endLocal.difference(startLocal);
}

@immutable
class DeviceChannelInfo {
  final int id;
  final String name;
  final bool enabled;
  final String resDesc;

  const DeviceChannelInfo({
    required this.id,
    required this.name,
    required this.enabled,
    this.resDesc = '',
  });
}