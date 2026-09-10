import 'package:flutter/foundation.dart';

@immutable
class RecordingSegment {
  final String trackId;
  final DateTime startUtc;
  final DateTime endUtc;
  final String? contentType;
  final String? codecType;
  final String? playbackUri;
  final String? name;

  const RecordingSegment({
    required this.trackId,
    required this.startUtc,
    required this.endUtc,
    this.contentType,
    this.codecType,
    this.playbackUri,
    this.name,
  });

  bool get isTiming =>
      contentType?.contains('timing') ?? (name != null && name!.contains('timing'));

  Duration get duration => endUtc.difference(startUtc);
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