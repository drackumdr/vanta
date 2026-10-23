import '../models/device_model.dart';
import 'hikvision_service.dart' show compactDeviceTime;

/// Construye URLs RTSP según la marca del dispositivo.
class RtspUrlBuilder {
  static String _cred(Device d) =>
      '${Uri.encodeComponent(d.username)}:${Uri.encodeComponent(d.password)}';

  static String _head(Device d) => 'rtsp://${_cred(d)}@${d.host}:${d.rtspPort}';

  /// Vivo. Hikvision: /Streaming/Channels/{ch}01|02.
  /// Dahua: /cam/realmonitor?channel=N&subtype=0|1.
  static String live(Device d, int channel, {required bool main}) {
    if (d.brand == DeviceBrand.dahua) {
      return '${_head(d)}/cam/realmonitor'
          '?channel=$channel&subtype=${main ? 0 : 1}';
    }
    final ch = channel >= 100 ? channel ~/ 100 : channel;
    final id = '$ch${main ? '01' : '02'}';
    return '${_head(d)}/Streaming/Channels/$id';
  }

  /// Playback por ventana de tiempo (hora local del dispositivo).
  /// Hikvision: /Streaming/tracks/{ch}01?starttime=...z&endtime=...z
  /// Dahua: /cam/playback?channel=N&starttime=YYYY_MM_DD_HH_MM_SS&endtime=...
  static String playback(
    Device d,
    int channel,
    DateTime startLocal,
    DateTime endLocal,
  ) {
    if (d.brand == DeviceBrand.dahua) {
      return '${_head(d)}/cam/playback?channel=$channel&subtype=0'
          '&starttime=${_dahuaTime(startLocal)}'
          '&endtime=${_dahuaTime(endLocal)}';
    }
    final ch = channel >= 100 ? channel ~/ 100 : channel;
    final track = '$ch' '01';
    return '${_head(d)}/Streaming/tracks/$track'
        '?starttime=${compactDeviceTime(startLocal)}'
        '&endtime=${compactDeviceTime(endLocal)}';
  }

  /// Playback a partir del playbackURI devuelto por CMS (reescrito con
  /// credenciales). Solo aplica a Hikvision; Dahua no expone playbackURI.
  static String? fromPlaybackUri(
    Device d,
    String? playbackUri, {
    DateTime? startLocal,
    DateTime? endLocal,
  }) {
    if (playbackUri == null || playbackUri.isEmpty) return null;
    var url = playbackUri.replaceFirst('rtsp://', 'rtsp://${_cred(d)}@');
    if (startLocal != null && endLocal != null) {
      url = url
          .replaceAll(
            RegExp(r'starttime=\d{8}t\d{6}z?', caseSensitive: false),
            'starttime=${compactDeviceTime(startLocal)}',
          )
          .replaceAll(
            RegExp(r'endtime=\d{8}t\d{6}z?', caseSensitive: false),
            'endtime=${compactDeviceTime(endLocal)}',
          );
    }
    return url;
  }
}

/// Hora local en formato Dahua: YYYY_MM_DD_HH_MM_SS.
String _dahuaTime(DateTime t) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${t.year}_${p(t.month)}_${p(t.day)}'
      '_${p(t.hour)}_${p(t.minute)}_${p(t.second)}';
}
