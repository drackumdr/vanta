import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../models/device_model.dart';
import '../models/recording_models.dart';
import 'isapi_client.dart';
import 'recording_service.dart';

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
class HikvisionService implements RecordingService {
  HikvisionService(
    this.device, {
    this.timeout = const Duration(seconds: 8),
    IsapiClient? client,
  }) : _injectedClient = client;

  final Device device;
  final Duration timeout;
  final IsapiClient? _injectedClient;
  static final Map<String, Duration> _offsetCache = {};

  IsapiClient get _api =>
      _injectedClient ??
      IsapiClient(
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

  /// Obtiene la lista de canales del dispositivo.
  /// Soporta DVR analógico (/ISAPI/System/Video/inputs/channels),
  /// NVR/canales IP (/ISAPI/ContentMgmt/InputProxy/channels) y fallback (/ISAPI/Streaming/channels).
  Future<List<DeviceChannelInfo>> fetchChannels() async {
    final channels = <DeviceChannelInfo>[];

    // 1. Canales analógicos (DVR convencional o híbrido)
    try {
      final res = await _api.get('/ISAPI/System/Video/inputs/channels');
      final doc = XmlDocument.parse(res.body);
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
    } catch (_) {
      // Puede ser un NVR que no soporta entradas analógicas
    }

    // 2. Canales IP Proxy (NVRs como DS-7616NI o cámaras IP enlazadas)
    if (channels.isEmpty) {
      try {
        final res = await _api.get('/ISAPI/ContentMgmt/InputProxy/channels');
        final doc = XmlDocument.parse(res.body);
        for (final ch in doc.findAllElements('InputProxyChannel')) {
          int intOf(String name) =>
              int.tryParse(ch.getElement(name)?.innerText.trim() ?? '') ?? 0;
          String text(String name) => ch.getElement(name)?.innerText.trim() ?? '';
          final id = intOf('id');
          if (id <= 0) continue;
          final port = ch.getElement('sourceInputPortDescriptor');
          final ip = port?.getElement('ipAddress')?.innerText.trim() ?? '';
          final model = port?.getElement('model')?.innerText.trim() ?? '';
          final rawName = text('name');
          final name = rawName.isNotEmpty && rawName != 'Camera 01'
              ? rawName
              : (model.isNotEmpty ? 'CH$id · $model' : 'Cámara $id');
          channels.add(DeviceChannelInfo(
            id: id,
            name: name,
            enabled: ip.isNotEmpty || model.isNotEmpty,
            resDesc: model.isNotEmpty ? model : ip,
          ));
        }
      } catch (_) {
        // Continuar con fallback de streaming si falla
      }
    }

    // 3. Fallback con canales de streaming
    if (channels.isEmpty) {
      try {
        final res = await _api.get('/ISAPI/Streaming/channels');
        final doc = XmlDocument.parse(res.body);
        final seenIds = <int>{};
        for (final ch in doc.findAllElements('StreamingChannel')) {
          final idStr = ch.getElement('id')?.innerText.trim() ?? '';
          final dynId = int.tryParse(
                ch.getElement('Video')?.getElement('dynVideoInputChannelID')?.innerText.trim() ?? '',
              ) ??
              (int.tryParse(idStr) != null ? int.parse(idStr) ~/ 100 : 0);
          if (dynId <= 0 || seenIds.contains(dynId)) continue;
          seenIds.add(dynId);
          final enabled = ch.getElement('enabled')?.innerText.trim().toLowerCase() == 'true';
          final chName = ch.getElement('channelName')?.innerText.trim() ?? '';
          channels.add(DeviceChannelInfo(
            id: dynId,
            name: chName.isNotEmpty && chName != idStr ? chName : 'Cámara $dynId',
            enabled: enabled,
            resDesc: '',
          ));
        }
      } catch (_) {
        // Ignorar
      }
    }

    channels.sort((a, b) => a.id.compareTo(b.id));
    return channels;
  }

  /// GET /ISAPI/System/time — offset UTC del dispositivo (con cache estática).
  @override
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
  @override
  Future<List<RecordingSegment>> searchRecordings({
    required int channel,
    required DateTime start,
    required DateTime end,
    int maxResults = 50,
    bool metadataAll = true,
  }) async {
    final searchId = _uuid();
    final trackId = '$channel' '01';

    // El clásico (CMSearchDescription) exige hora local con sufijo 'Z';
    // el formato con offset (-06:00) lo rechaza con badXmlContent.
    final xml = '''
<?xml version="1.0" encoding="utf-8"?>
<CMSearchDescription>
  <searchID>$searchId</searchID>
  <trackList><trackID>$trackId</trackID></trackList>
  <timeSpanList><timeSpan>
    <startTime>${_formatZ(start)}</startTime>
    <endTime>${_formatZ(end)}</endTime>
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
      final startLocal = parseHikvisionTime(text(span, 'startTime'));
      final endLocal = parseHikvisionTime(text(span, 'endTime'));
      if (track.isEmpty || startLocal == null || endLocal == null) continue;

      final media = item.getElement('mediaSegmentDescriptor');
      final recordType = item
              .findAllElements('metadataDescriptor')
              .firstOrNull
              ?.innerText
              .trim() ??
          text(media, 'recordType');

      segments.add(RecordingSegment(
        trackId: track,
        startLocal: startLocal,
        endLocal: endLocal,
        contentType: text(media, 'contentType'),
        codecType: text(media, 'codecType'),
        playbackUri: text(media, 'playbackURI'),
        name: recordType.isEmpty ? text(media, 'name') : recordType,
      ));
    }
    segments.sort((a, b) => a.startLocal.compareTo(b.startLocal));
    return segments;
  }

  /// GET /ISAPI/ContentMgmt/SearchByTargetType/capabilities?format=json.
  /// Devuelve los tipos de objetivo que soporta el NVR (human, vehicle, ...).
  /// Lista vacía = función no soportada.
  @override
  Future<List<String>> fetchSearchTargetTypes() async {
    try {
      final res = await _api.get(
        '/ISAPI/ContentMgmt/SearchByTargetType/capabilities?format=json',
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final cap = data['SearchDescriptionCap'] as Map<String, dynamic>?;
      final opt = (cap?['targetTypes'] as Map<String, dynamic>?)?['@opt'];
      if (opt is! List) return const [];
      return opt.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// POST /ISAPI/ContentMgmt/SearchByTargetType?format=json — búsqueda de
  /// grabaciones por tipo de objetivo detectado (humano/vehículo).
  /// [start]/[end] en hora local del dispositivo; un canal por request.
  @override
  Future<List<RecordingSegment>> searchByTargetType({
    required int channel,
    required List<String> targetTypes,
    required DateTime start,
    required DateTime end,
    int maxResults = 300,
  }) async {
    final offset = await fetchDeviceUtcOffset();
    final body = jsonEncode({
      'SearchDescription': {
        'searchID': _uuid(),
        'searchResultPosition': 0,
        'maxResults': maxResults,
        'SearchCondList': [
          {
            'channelID': channel,
            'targetTypes': targetTypes,
            'searchTimeList': [
              {
                'searchTime': {
                  'startTime': _formatXmlDate(start, offset),
                  'endTime': _formatXmlDate(end, offset),
                },
              },
            ],
          },
        ],
      },
    });

    final res = await _api.post(
      '/ISAPI/ContentMgmt/SearchByTargetType?format=json',
      body: body,
      contentType: 'application/json',
    );

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final result = data['SearchResult'];
    if (result is! Map<String, dynamic>) {
      final status = (data['statusCode'] ?? data['StatusCode'] ?? 'unknown')
          .toString();
      throw IsapiException(
          ApiErrorKind.server, 'Búsqueda por tipo rechazada (código $status)');
    }
    if (result['responseStatus'] != true &&
        result['responseStatus']?.toString().toLowerCase() != 'true') {
      throw IsapiException(
        ApiErrorKind.server,
        'Búsqueda por tipo rechazada: '
        '${result['responseStatusStrg'] ?? result['statusString'] ?? ''}',
      );
    }

    DateTime? startLocalOf(Object? t) => parseHikvisionTime(t?.toString() ?? '');

    final segments = <RecordingSegment>[];
    for (final match in (result['matchList'] as List? ?? const [])) {
      if (match is! Map<String, dynamic>) continue;
      for (final rec in (match['RecordInfoList'] as List? ?? const [])) {
        if (rec is! Map<String, dynamic>) continue;
        final rt = rec['RecordTime'];
        if (rt is! Map<String, dynamic>) continue;
        final s = startLocalOf(rt['startTime']?.toString());
        final e = startLocalOf(rt['endTime']?.toString());
        if (s == null || e == null) continue;
        segments.add(RecordingSegment(
          trackId: '$channel' '01',
          startLocal: s,
          endLocal: e,
          name: (match['targetTypes'] as List? ?? const [])
              .whereType<String>()
              .join(','),
        ));
      }
    }
    segments.sort((a, b) => a.startLocal.compareTo(b.startLocal));
    return segments;
  }

  /// Parsea marcas de tiempo XML de Hikvision.
  /// Los valores representan el reloj local del dispositivo, incluso cuando
  /// el firmware añade sufijo 'Z' (ej. 2026-09-11T07:06:57Z) o zona horaria.
  static DateTime? parseHikvisionTime(String text) {
    if (text.isEmpty) return null;
    final clean = text.replaceAll(RegExp(r'[Zz]|([+-]\d{2}:\d{2})$'), '');
    return DateTime.tryParse(clean);
  }

  /// Hora local del dispositivo con sufijo 'Z' (formato exigido por el clásico).
  static String _formatZ(DateTime local) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${p(local.month)}-${p(local.day)}'
        'T${p(local.hour)}:${p(local.minute)}:${p(local.second)}Z';
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

  /// Consulta si el grabador tiene habilitado el cifrado de flujo (Hik-Connect / EZVIZ).
  Future<StreamEncryptionStatus> checkStreamEncryption() async {
    try {
      final res = await _api.get('/ISAPI/System/Network/EZVIZ');
      if (res.statusCode == 404 || res.statusCode == 400) {
        return const StreamEncryptionUnsupported();
      }
      if (res.statusCode == 401) {
        return const StreamEncryptionError('Autenticación fallida (401) al verificar cifrado');
      }
      if (res.statusCode != 200) {
        return StreamEncryptionError('Código de respuesta HTTP ${res.statusCode}');
      }

      final doc = XmlDocument.parse(res.body);
      final ezviz = doc.findAllElements('EZVIZ').firstOrNull;
      if (ezviz == null) {
        return const StreamEncryptionUnsupported();
      }

      final enc = doc
              .findAllElements('streamEncrypteEnabled')
              .firstOrNull
              ?.innerText
              .trim()
              .toLowerCase() ==
          'true';
      final code = doc
              .findAllElements('verificationCode')
              .firstOrNull
              ?.innerText
              .trim() ??
          '';

      if (enc) {
        return StreamEncryptionActive(verificationCode: code);
      } else {
        return const StreamEncryptionDisabled();
      }
    } on IsapiException catch (e) {
      if (e.kind == ApiErrorKind.notFound) {
        return const StreamEncryptionUnsupported();
      }
      return StreamEncryptionError(e.message);
    } catch (e) {
      return StreamEncryptionError(e.toString());
    }
  }

  /// Permite activar o desactivar el cifrado de flujo directamente desde VANTA.
  Future<bool> setStreamEncryption(bool enable, {String? verificationCode}) async {
    try {
      final current = await _api.get('/ISAPI/System/Network/EZVIZ');
      final doc = XmlDocument.parse(current.body);
      final ezviz = doc.findAllElements('EZVIZ').firstOrNull;
      if (ezviz == null) return false;

      final rawCode = (verificationCode != null && verificationCode.isNotEmpty)
          ? verificationCode
          : (doc.findAllElements('verificationCode').firstOrNull?.innerText.trim() ?? '');

      final safeCode = _escapeXml(rawCode);

      final xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<EZVIZ version="1.0" xmlns="http://www.std-cgi.com/ver20/XMLSchema">\n'
          '  <enabled>true</enabled>\n'
          '  <registerStatus>true</registerStatus>\n'
          '  <redirect>false</redirect>\n'
          '  <serverAddress>\n'
          '    <addressingFormatType>hostname</addressingFormatType>\n'
          '    <hostName>litedev.us.hik-connect.com</hostName>\n'
          '  </serverAddress>\n'
          '  <verificationCode>$safeCode</verificationCode>\n'
          '  <enabledTiming>false</enabledTiming>\n'
          '  <streamEncrypteEnabled>$enable</streamEncrypteEnabled>\n'
          '</EZVIZ>';

      final res = await _api.put(
        '/ISAPI/System/Network/EZVIZ',
        body: xml,
        contentType: 'application/xml',
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

/// Estado tipado del cifrado de flujo en grabadores Hikvision.
sealed class StreamEncryptionStatus {
  const StreamEncryptionStatus();
}

class StreamEncryptionActive extends StreamEncryptionStatus {
  final String verificationCode;
  const StreamEncryptionActive({required this.verificationCode});
}

class StreamEncryptionDisabled extends StreamEncryptionStatus {
  const StreamEncryptionDisabled();
}

class StreamEncryptionUnsupported extends StreamEncryptionStatus {
  const StreamEncryptionUnsupported();
}

class StreamEncryptionError extends StreamEncryptionStatus {
  final String message;
  const StreamEncryptionError(this.message);
}

/// Compacta hora local del dispositivo para URL RTSP (formato Hikvision minúsculo).
String compactDeviceTime(DateTime local) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${local.year}${p(local.month)}${p(local.day)}'
      't${p(local.hour)}${p(local.minute)}${p(local.second)}z';
}