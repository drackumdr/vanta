import 'package:flutter/foundation.dart';

enum DeviceKind { dvr, nvr, ipc }

enum DeviceBrand { hikvision, dahua }

extension DeviceBrandX on DeviceBrand {
  String get label => switch (this) {
    DeviceBrand.hikvision => 'Hikvision',
    DeviceBrand.dahua => 'Dahua',
  };

  static DeviceBrand fromName(String? name) => switch (name) {
    'dahua' => DeviceBrand.dahua,
    _ => DeviceBrand.hikvision,
  };
}

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
  final DeviceBrand brand;
  final String host;
  final int port;
  final int rtspPort;
  final String username;
  final String password;
  final int channelCount;
  final List<int> channelIds;
  final bool https;
  final bool streamEncryption;
  final String verificationCode;
  final DateTime createdAt;

  const Device({
    required this.id,
    required this.name,
    required this.kind,
    this.brand = DeviceBrand.hikvision,
    required this.host,
    this.port = 80,
    this.rtspPort = 554,
    required this.username,
    required this.password,
    this.channelCount = 0,
    this.channelIds = const [],
    this.https = false,
    this.streamEncryption = false,
    this.verificationCode = '',
    required this.createdAt,
  });

  Device copyWith({
    String? name,
    DeviceKind? kind,
    DeviceBrand? brand,
    String? host,
    int? port,
    int? rtspPort,
    String? username,
    String? password,
    int? channelCount,
    List<int>? channelIds,
    bool? https,
    bool? streamEncryption,
    String? verificationCode,
  }) {
    return Device(
      id: id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      brand: brand ?? this.brand,
      host: host ?? this.host,
      port: port ?? this.port,
      rtspPort: rtspPort ?? this.rtspPort,
      username: username ?? this.username,
      password: password ?? this.password,
      channelCount: channelCount ?? this.channelCount,
      channelIds: channelIds ?? this.channelIds,
      https: https ?? this.https,
      streamEncryption: streamEncryption ?? this.streamEncryption,
      verificationCode: verificationCode ?? this.verificationCode,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'brand': brand.name,
    'host': host,
    'port': port,
    'rtspPort': rtspPort,
    'username': username,
    'channelCount': channelCount,
    'channelIds': channelIds,
    'https': https,
    'streamEncryption': streamEncryption,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Device.fromJson(
    Map<String, dynamic> json, {
    String password = '',
    String verificationCode = '',
  }) {
    return Device(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      kind: DeviceKindX.fromName(json['kind'] as String?),
      brand: DeviceBrandX.fromName(json['brand'] as String?),
      host: (json['host'] as String?) ?? '',
      port: (json['port'] as num?)?.toInt() ?? 80,
      rtspPort: (json['rtspPort'] as num?)?.toInt() ?? 554,
      username: (json['username'] as String?) ?? '',
      password: password,
      channelCount: (json['channelCount'] as num?)?.toInt() ?? 0,
      channelIds: ((json['channelIds'] as List?) ?? const [])
          .whereType<num>()
          .map((id) => id.toInt())
          .where((id) => id > 0)
          .toList(growable: false),
      https: (json['https'] as bool?) ?? false,
      streamEncryption: (json['streamEncryption'] as bool?) ?? false,
      verificationCode: verificationCode.isNotEmpty
          ? verificationCode
          : ((json['verificationCode'] as String?) ?? ''),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
