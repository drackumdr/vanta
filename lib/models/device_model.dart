import 'package:flutter/foundation.dart';

enum DeviceKind { dvr, nvr, ipc }

extension DeviceKindX on DeviceKind {
  String get label => switch (this) {
        DeviceKind.dvr => 'DVR',
        DeviceKind.nvr => 'NVR',
        DeviceKind.ipc => 'Cámara IP',
      };

  static DeviceKind fromName(String? name) => switch (name) {
        'nvr' => DeviceKind.nvr,
        'ipc' => DeviceKind.ipc,
        _ => DeviceKind.dvr,
      };
}

@immutable
class Device {
  final String id;
  final String name;
  final DeviceKind kind;
  final String host;
  final int port;
  final int rtspPort;
  final String username;
  final String password;
  final int channelCount;
  final bool https;
  final DateTime createdAt;

  const Device({
    required this.id,
    required this.name,
    required this.kind,
    required this.host,
    this.port = 80,
    this.rtspPort = 554,
    required this.username,
    required this.password,
    this.channelCount = 0,
    this.https = false,
    required this.createdAt,
  });

  Device copyWith({
    String? name,
    DeviceKind? kind,
    String? host,
    int? port,
    int? rtspPort,
    String? username,
    String? password,
    int? channelCount,
    bool? https,
  }) {
    return Device(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      host: host ?? this.host,
      port: port ?? this.port,
      rtspPort: rtspPort ?? this.rtspPort,
      username: username ?? this.username,
      password: password ?? this.password,
      channelCount: channelCount ?? this.channelCount,
      https: https ?? this.https,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'host': host,
        'port': port,
        'rtspPort': rtspPort,
        'username': username,
        'channelCount': channelCount,
        'https': https,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Device.fromJson(Map<String, dynamic> json, {String password = ''}) {
    return Device(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      kind: DeviceKindX.fromName(json['kind'] as String?),
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 80,
      rtspPort: (json['rtspPort'] as num?)?.toInt() ?? 554,
      username: (json['username'] as String?) ?? '',
      password: password,
      channelCount: (json['channelCount'] as num?)?.toInt() ?? 0,
      https: (json['https'] as bool?) ?? false,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
              DateTime.now(),
    );
  }
}