import 'package:flutter/foundation.dart';

import 'device_model.dart';

@immutable
class Camera {
  /// Stable id: "${deviceId}:$channel".
  final String id;
  final String deviceId;
  final int channel;
  final String name;
  final String resDesc;
  final bool enabled;

  const Camera({
    required this.id,
    required this.deviceId,
    required this.channel,
    required this.name,
    this.resDesc = '',
    this.enabled = true,
  });

  static String idFor(String deviceId, int channel) => '$deviceId:$channel';

  factory Camera.forDevice(
    Device device,
    int channel, {
    String? name,
    String resDesc = '',
    bool enabled = true,
  }) {
    return Camera(
      id: idFor(device.id, channel),
      deviceId: device.id,
      channel: channel,
      name: name ?? '${device.name} · CH$channel',
      resDesc: resDesc,
      enabled: enabled,
    );
  }

  bool get videoSignal => resDesc.trim().toUpperCase() != 'NO VIDEO';
}