import 'dart:convert';

import '../models/device_model.dart';
import '../models/recording_models.dart';
import 'hikvision_service.dart' show DeviceInfoResult;
import 'isapi_client.dart';
import 'recording_service.dart';

/// Cliente CGI de Dahua (búsqueda de grabaciones vía mediaFileFind).
/// Reutiliza [IsapiClient] (Digest RFC-2617) para resolver el 401.
class DahuaService implements RecordingService {
  DahuaService(
    this.device, {
    this.timeout = const Duration(seconds: 8),
    IsapiClient? client,
  }) : _injectedClient = client;

  final Device device;
  final Duration timeout;
  final IsapiClient? _injectedClient;

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

  // ------------------------------------------------------------ deviceInfo
  /// GET /cgi-bin/magicBox.cgi?action=getDeviceType — prueba de conexión.
  Future<DeviceInfoResult> fetchDeviceInfo() async {
    final devType = await _cgi('magicBox.cgi', 'action=getDeviceType').catchError((_) => '');
    String sn = _value(devType, 'sn') ?? '';
    final model = _value(devType, 'type') ?? '';
    String version = '';

    if (sn.isEmpty) {
      try {
        final snBody = await _cgi('magicBox.cgi', 'action=getSerialNo');
        sn = _value(snBody, 'sn') ?? '';
      } catch (_) {}
    }
    try {
      final verBody = await _cgi('magicBox.cgi', 'action=getSoftwareVersion');
      version = _value(verBody, 'version') ?? '';
    } catch (_) {}

    return DeviceInfoResult(
      deviceName: model.isNotEmpty ? model : device.name,
      model: model,
      serialNumber: sn,
      firmwareVersion: version,
      macAddress: '',
    );
  }

  /// Canales 1..N. Descubre nombres reales vía ChannelTitle o conteo vía
  /// getSystemInfo / channelCount guardado.
  Future<List<DeviceChannelInfo>> fetchChannels() async {
    try {
      final titleBody = await _cgi(
        'configManager.cgi',
        'action=getConfig&name=ChannelTitle',
      );
      final re = RegExp(r'table\.ChannelTitle\[(\d+)\]\.Name=(.*)');
      final channels = <DeviceChannelInfo>[];
      for (final m in re.allMatches(titleBody)) {
        final idx = int.tryParse(m.group(1)!);
        if (idx != null) {
          final chId = idx + 1;
          final name = m.group(2)?.trim().replaceAll('"', '') ?? '';
          channels.add(
            DeviceChannelInfo(
              id: chId,
              name: name.isNotEmpty ? name : 'Canal $chId',
              enabled: true,
            ),
          );
        }
      }
      if (channels.isNotEmpty) {
        channels.sort((a, b) => a.id.compareTo(b.id));
        return channels;
      }
    } catch (_) {}

    var count = device.channelCount;
    if (count == 0) {
      try {
        final sysInfo = await _cgi('magicBox.cgi', 'action=getSystemInfo');
        count = int.tryParse(_value(sysInfo, 'videoInputNum') ?? '') ?? 0;
      } catch (_) {}
    }
    if (count <= 0) count = 1;
    return [
      for (var ch = 1; ch <= count; ch++)
        DeviceChannelInfo(id: ch, name: 'Canal $ch', enabled: true),
    ];
  }

  // -------------------------------------------------- búsqueda grabaciones
  /// GET /cgi-bin/mediaFileFind.cgi — lista las grabaciones de [channel]
  /// entre [start] y [end] (hora local del dispositivo).
  @override
  Future<List<RecordingSegment>> searchRecordings({
    required int channel,
    required DateTime start,
    required DateTime end,
    int maxResults = 300,
  }) async {
    final id = _value(
      await _cgi('mediaFileFind.cgi', 'action=factory.create'),
      'result',
    );
    if (id == null || id.isEmpty) {
      throw IsapiException(ApiErrorKind.server, 'Dahua: sin sesión de búsqueda');
    }

    final segments = <RecordingSegment>[];
    try {
      await _cgi(
        'mediaFileFind.cgi',
        'action=findFile&object=$id'
        '&condition.Channel=$channel'
        '&condition.StartTime=${Uri.encodeComponent(_xmlTime(start))}'
        '&condition.EndTime=${Uri.encodeComponent(_xmlTime(end))}'
        '&condition.Types%5B0%5D=dav'
        '&condition.Types%5B1%5D=mp4',
      );

      for (var page = 0; page < 50 && segments.length < maxResults; page++) {
        final body =
            await _cgi('mediaFileFind.cgi', 'action=findNextFile&object=$id&count=100');
        final items = _parseItems(body, channel);
        if (items.isEmpty) break;
        segments.addAll(items);
      }
    } finally {
      try {
        await _cgi('mediaFileFind.cgi', 'action=close&object=$id');
        await _cgi('mediaFileFind.cgi', 'action=destroy&object=$id');
      } catch (_) {
        // La sesión se libera igual en el equipo; no bloquea el resultado.
      }
    }

    segments.sort((a, b) => a.startLocal.compareTo(b.startLocal));
    return segments.take(maxResults).toList();
  }

  /// Respuesta: items[0].StartTime=2026-10-22 09:00:00, items[0].EndTime=...
  List<RecordingSegment> _parseItems(String body, int channel) {
    final starts = <int, DateTime>{};
    final ends = <int, DateTime>{};
    final re = RegExp(r'items\[(\d+)\]\.(StartTime|EndTime)=(.*)');
    for (final m in re.allMatches(body)) {
      final i = int.parse(m.group(1)!);
      final raw = m.group(3)!.trim().replaceAll('"', '').replaceAll("'", '');
      final t = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
      if (t == null) continue;
      (m.group(2) == 'StartTime' ? starts : ends)[i] = t;
    }
    return [
      for (final i in starts.keys)
        if (ends[i] != null)
          RecordingSegment(
            trackId: '$channel' '01',
            startLocal: starts[i]!,
            endLocal: ends[i]!,
          ),
    ];
  }

  // ------------------------------------------------------------- helpers
  Future<String> _cgi(String endpoint, String query) async {
    final r = await _api.get('/cgi-bin/$endpoint?$query');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// Extrae `key=value` (primera coincidencia) del texto plano de Dahua.
  static String? _value(String body, String key) {
    final m = RegExp('^$key=(.*)\$', multiLine: true).firstMatch(body);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Hora local del dispositivo: YYYY-MM-DD HH:MM:SS.
  static String _xmlTime(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)}'
        ' ${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  // -------------------------------------------- compat con la UI de grabaciones
  // La UI de reproducir comparte estos métodos con HikvisionService; Dahua no
  // tiene offset vía ISAPI (usa hora local) ni búsqueda por tipo de objetivo.

  @override
  Future<Duration> fetchDeviceUtcOffset() async => Duration.zero;

  @override
  Future<List<String>> fetchSearchTargetTypes() async => const [];

  @override
  Future<List<RecordingSegment>> searchByTargetType({
    required int channel,
    required List<String> targetTypes,
    required DateTime start,
    required DateTime end,
    int maxResults = 300,
  }) async =>
      const [];
}
