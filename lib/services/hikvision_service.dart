import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../models/device_model.dart';
import '../models/recording_models.dart';
import 'isapi_client.dart';

class DeviceInfoResult {
  final String deviceName;
  final String model;
  final String serialNumber;
  final String firmwareVersion;
  final String macAddress;
  const DeviceInfoResult({
    required this.deviceName,
    required this.model,
    required this.serialNumber,
    required this.firmwareVersion,
    required this.macAddress,
  });
}

/// Servicio ISAPI de videovigilancia (port de "control de acceso"/BioAccess PRO).
class HikvisionService {
  HikvisionService(this.device, {this.timeout = const Duration(seconds: 8)});

  final Device device;
  final Duration timeout;
  static final Map<String, Duration> _offsetCache = {};

  IsapiClient get _api => IsapiClient(
        host: device.host,
        port: device.port,
        username: device.username,
        password: device.password,
        https: device.https,
        timeout: timeout,
      );

  /// GET /ISAPI/System/deviceInfo — prueba de conexión + identificación.
  Future<DeviceInfoResult> fetchDeviceInfo() async {
    final res = await _api.get('/ISAPI/System/deviceInfo');
    final doc = XmlDocument.parse(res.body);
    String text(String name) =>
        doc.findAllElements(name).firstOrNull?.innerText.trim() ?? '';
    final model = text('model');
    final deviceName = text('deviceName');
    return DeviceInfoResult(
      deviceName: deviceName,
      model: model,
      serialNumber: text('serialNumber'),
      firmwareVersion: text('firmwareVersion'),
      macAddress: text('macAddress'),
    );
  }

  /// GET /ISAPI/System/Video/inputs/channels — listado de canales.
  Future<List<DeviceChannelInfo>> fetchChannels() async {
    final res = await _api.get('/ISAPI/System/Video/inputs/channels');
    final doc = XmlDocument.parse(res.body);
    final channels = <DeviceChannelInfo>[];
    for (final ch in doc.findAllElements('VideoInputChannel')) {
      int intOf(String name) =>
          int.tryParse(ch.getElement(name)?.innerText.trim() ?? '') ?? 0;
      String text(String name) => ch.getElement(name)?.innerText.trim() ?? '';
      final id = intOf('id');
      if (id <= 0) continue;
      channels.add(DeviceChannelInfo(
        id: id,
        name: text('name'),
        enabled: text('videoInputEnabled').toLowerCase() == 'true',
        resDesc: text('resDesc'),
      ));
    }
    channels.sort((a, b) => a.id.compareTo(b.id));
    return channels;
  }

  /// GET /ISAPI/System/time — offset UTC del dispositivo (con cache estática).
  Future<Duration> fetchDeviceUtcOffset() async {
    final cached = _offsetCache[device.id];
    if (cached != null) return cached;

    final res = await _api.get('/ISAPI/System/time');
    final doc = XmlDocument.parse(res.body);
    final localTime =
        doc.findAllElements('localTime').firstOrNull?.innerText.trim() ?? '';
    final timeZone =
        doc.findAllElements('timeZone').firstOrNull?.innerText.trim() ?? '';
    final offset = _parseOffset(localTime) ?? _parseZoneText(timeZone) ?? Duration.zero;
    _offsetCache[device.id] = offset;
    return offset;
  }

  /// GET /ISAPI/Streaming/channels/{ch}{01|02}/picture — snapshot JPEG.
  Future<Uint8List> snapshot(int channel, {bool main = true}) async {
    final sid = '$channel${main ? '01' : '02'}';
    final res =
        await _api.getBytes('/ISAPI/Streaming/channels/$sid/picture');
    final data = res.bodyBytes;
    if (data.length < 1024 || data[0] != 0xFF || data[1] != 0xD8) {
      throw IsapiException(ApiErrorKind.server, 'Respuesta no es JPEG válido');
    }
    return data;
  }

  /// POST /ISAPI/ContentMgmt/search — búsqueda de grabaciones (CMS).
  /// [start]/[end] deben estar en hora local del dispositivo.
  Future<List<RecordingSegment>> searchRecordings({
    required int channel,
    required DateTime start,
    required DateTime end,
    int maxResults = 50,
    bool metadataAll = true,
  }) async {
    final offset = await fetchDeviceUtcOffset();
    final searchId = _uuid();
    final trackId = '$channel' '01';

    final xml = '''
<?xml version="1.0" encoding="utf-8"?>
<CMSearchDescription>
  <searchID>$searchId</searchID>
  <trackList><trackID>$trackId</trackID></trackList>
  <timeSpanList><timeSpan>
    <startTime>${_formatXmlDate(start, offset)}</startTime>
    <endTime>${_formatXmlDate(end, offset)}</endTime>
  </timeSpan></timeSpanList>
  <maxResults>$maxResults</maxResults>
  <searchResultPostion>0</searchResultPostion>
  <metadataList><metadataDescriptor>//recordType.meta.std-cgi.com</metadataDescriptor></metadataList>
</CMSearchDescription>''';

    final res = await _api.post(
      '/ISAPI/ContentMgmt/search',
      body: xml,
      contentType: 'application/xml; charset=UTF-8',
    );

    final doc = XmlDocument.parse(res.body);
    final ok =
        doc.findAllElements('responseStatus').firstOrNull?.innerText.trim() == 'true';
    if (!ok) {
      final msg = doc
              .findAllElements('responseStatusStrg')
              .firstOrNull
              ?.innerText
              .trim() ??
          '';
      throw IsapiException(ApiErrorKind.server, 'Búsqueda rechazada: $msg');
    }

    final segments = <RecordingSegment>[];
    for (final item in doc.findAllElements('searchMatchItem')) {
      String text(XmlElement? parent, String name) =>
          parent?.getElement(name)?.innerText.trim() ?? '';

      final track = text(item, 'trackID');
      final span = item.getElement('timeSpan');
      final startUtc = DateTime.tryParse(text(span, 'startTime'));
      final endUtc = DateTime.tryParse(text(span, 'endTime'));
      if (track.isEmpty || startUtc == null || endUtc == null) continue;

      final media = item.getElement('mediaSegmentDescriptor');
      final recordType = item
          .getElement('metadataMatches')
          ?.getElement('metadataDescriptor')
          ?.innerText
          .trim() ??
          '';

      segments.add(RecordingSegment(
        trackId: track,
        startUtc: startUtc.toUtc(),
        endUtc: endUtc.toUtc(),
        contentType: text(media, 'contentType'),
        codecType: text(media, 'codecType'),
        playbackUri: text(media, 'playbackURI'),
        name: recordType.isEmpty ? text(media, 'name') : recordType,
      ));
    }
    segments.sort((a, b) => a.startUtc.compareTo(b.startUtc));
    return segments;
  }

  /// Formatea un DateTime (hora local del usuario) a XML con offset del dispositivo.
  static String _formatXmlDate(DateTime local, Duration offset) {
    String p(int v) => v.toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    final total = offset.inMinutes.abs();
    final oh = (total ~/ 60).toString().padLeft(2, '0');
    final om = (total % 60).toString().padLeft(2, '0');
    return '${local.year}-${p(local.month)}-${p(local.day)}'
        'T${p(local.hour)}:${p(local.minute)}:${p(local.second)}$sign$oh:$om';
  }

  /// Convierte un instante UTC a hora local del dispositivo.
  static DateTime toDeviceLocal(DateTime utc, Duration offset) => utc.add(offset);

  static Duration? _parseOffset(String? localTime) {
    if (localTime == null) return null;
    final m = RegExp(r'([+-])(\d{2}):(\d{2})$').firstMatch(localTime);
    if (m == null) return null;
    final minutes = int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
    return Duration(minutes: m.group(1) == '-' ? -minutes : minutes);
  }

  static Duration? _parseZoneText(String? zone) {
    if (zone == null) return null;
    final m = RegExp(r'([+-])(\d{1,2}):(\d{2})(?::\d{2})?').firstMatch(zone);
    if (m == null) return null;
    final minutes = int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
    return Duration(minutes: m.group(1) == '-' ? -minutes : minutes);
  }

  static String _uuid() {
    // UUID sin dependencia extra (suficiente para searchID).
    final rnd = DateTime.now().microsecondsSinceEpoch;
    final stripped = '$rnd$rnd'.padRight(32, '0');
    final chars = stripped.substring(0, 32).toUpperCase();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-'
        '${chars.substring(12, 16)}-${chars.substring(16, 20)}-'
        '${chars.substring(20, 32)}';
  }
}

/// Compacta hora local del dispositivo para URL RTSP (formato Hikvision minúsculo).
String compactDeviceTime(DateTime local) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${local.year}${p(local.month)}${p(local.day)}'
      't${p(local.hour)}${p(local.minute)}${p(local.second)}z';
}