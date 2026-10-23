import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'video_sink.dart';

enum RenderState { idle, loading, ready, ended, error }

/// Sesión de un reproductor RTSP nativo (Media3/ExoPlayer) renderizado
/// en una textura Flutter. Una por cámara visible.
class RtspSession implements VideoSink {
  RtspSession(this.playerId, this.textureId);

  final int playerId;
  final int textureId;
  @override
  final ValueNotifier<RenderState> state = ValueNotifier(RenderState.loading);
  @override
  final ValueNotifier<String?> error = ValueNotifier(null);
  /// Aspecto real del stream (ancho/alto) cuando Media3 lo reporta.
  final ValueNotifier<double?> aspect = ValueNotifier(null);

  @override
  bool get isSubstream => _isSubstream;

  bool _isSubstream = false;
  bool _disposed = false;

  static const MethodChannel _channel = MethodChannel('vanta/rtsp');
  static const EventChannel _events = EventChannel('vanta/rtsp/events');
  static final Map<int, RtspSession> _sessions = {};
  static bool _listening = false;

  static Future<RtspSession> create(String url) async {
    _startListening();
    final result =
        await _channel.invokeMethod('create', <String, dynamic>{'url': url});
    final session = RtspSession(
      result['playerId'] as int,
      result['textureId'] as int,
    );
    _sessions[session.playerId] = session;
    return session;
  }

  static void _startListening() {
    if (_listening) return;
    _listening = true;
    _events.receiveBroadcastStream().listen((dynamic event) {
      final id = (event['playerId'] as num?)?.toInt();
      final type = event['type'] as String? ?? '';
      final payload = event['payload'] as String?;
      _sessions[id]?._handle(type, payload);
    });
  }

  void _handle(String type, String? payload) {
    switch (type) {
      case 'state':
        final s = int.tryParse(payload ?? '-1') ?? -1;
        _later(() {
          state.value = switch (s) {
            2 => RenderState.ready,
            3 => RenderState.error,
            0 => RenderState.idle,
            _ => RenderState.loading,
          };
          if (state.value == RenderState.ready) {
            error.value = null;
          } else if (state.value == RenderState.error && error.value == null) {
            error.value = 'Transmisión finalizada';
          }
        });
      case 'videoSize':
        final parts = payload?.split('x');
        final w = parts != null && parts.length == 2 ? int.tryParse(parts[0]) : null;
        final h = parts != null && parts.length == 2 ? int.tryParse(parts[1]) : null;
        if (w != null && h != null && w > 0 && h > 0) {
          final ratio = (w < h ||
                  (w == 960 && h == 1080) ||
                  (w == 640 && h == 720) ||
                  (w >= 1280 || h >= 720))
              ? (16 / 9)
              : (w / h);
          _later(() => aspect.value = ratio);
        }
      case 'error':
        _later(() {
          state.value = RenderState.error;
          error.value = payload ?? 'Error de reproducción';
        });
      default:
        break;
    }
  }

  void _later(VoidCallback update) {
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      update();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) update();
      });
    }
  }

  @override
  Future<void> open(String url) async {
    _isSubstream = url.contains('/02');
    try {
      await _channel.invokeMethod(
        'open',
        <String, dynamic>{'playerId': playerId, 'url': url},
      );
    } on PlatformException {
      _later(() {
        state.value = RenderState.error;
        error.value = 'No se pudo reproducir el video';
      });
    }
  }

  @override
  Future<void> play() async =>
      _channel.invokeMethod('play', <String, dynamic>{'playerId': playerId});

  @override
  Future<void> pause() async =>
      _channel.invokeMethod('pause', <String, dynamic>{'playerId': playerId});

  @override
  Future<void> setMuted(bool muted) async => _channel.invokeMethod(
        'mute',
        <String, dynamic>{'playerId': playerId, 'muted': muted},
      );

  @override
  Future<void> dispose() async {
    _disposed = true;
    _sessions.remove(playerId);
    try {
      await _channel.invokeMethod(
        'dispose',
        <String, dynamic>{'playerId': playerId},
      );
    } finally {
      _later(() => state.value = RenderState.idle);
    }
  }
}
