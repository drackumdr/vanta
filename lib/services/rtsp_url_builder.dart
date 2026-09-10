import '../models/device_model.dart';
import 'hikvision_service.dart' show compactDeviceTime;

/// Construye URLs RTSP de Hikvision (validado contra S16TURBOX V3.4.88).
class RtspUrlBuilder {
  static String _cred(Device d) =>
      '${Uri.encodeComponent(d.username)}:${Uri.encodeComponent(d.password)}';

  /// Live: rtsp://user:pass@host:554/Streaming/Channels/{ch}01|02
  static String live(Device d, int channel, {required bool main}) {
    final id = '$channel${main ? '01' : '02'}';
    return 'rtsp://${_cred(d)}@${d.host}:${d.rtspPort}/Streaming/Channels/$id';
  }

  /// Playback por ventana de tiempo (hora local del dispositivo).
  /// rtsp://user:pass@host:554/Streaming/tracks/{ch}01?starttime=...z&endtime=...z
  static String playback(
    Device d,
    int channel,
    DateTime startLocal,
    DateTime endLocal,
  ) {
    final track = '$channel' '01';
    return 'rtsp://${_cred(d)}@${d.host}:${d.rtspPort}/Streaming/tracks/$track'
        '?starttime=${compactDeviceTime(startLocal)}'
        '&endtime=${compactDeviceTime(endLocal)}';
  }

  /// Playback a partir del playbackURI devuelto por CMS (reescrito con credenciales).
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