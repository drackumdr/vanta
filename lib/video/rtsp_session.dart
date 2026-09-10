import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  @override
  bool get isSubstream => _isSubstream;

  bool _isSubstream = false;

  static const MethodChannel _channel = MethodChannel('vanta/rtsp');
  static const EventChannel _events = EventChannel('vanta/rtsp/events');
  static final Map<int, RtspSession> _sessions = {};
  static bool _listening = false;

  static Future<RtspSession> create(String url) async {
    final result =
        await _channel.invokeMethod('create', <String, dynamic>{'url': url});
    final session = RtspSession(
      result['playerId'] as int,
      result['textureId'] as int,
    );
    _sessions[session.playerId] = session;
    _startListening();
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
        state.value = switch (s) {
          2 => RenderState.ready,
          3 => RenderState.ended,
          0 => RenderState.idle,
          _ => RenderState.loading,
        };
        if (state.value == RenderState.ready) error.value = null;
      case 'error':
        state.value = RenderState.error;
        error.value = payload ?? 'Error de reproducción';
      default:
        break;
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
      state.value = RenderState.error;
      error.value = 'No se pudo reproducir el video';
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
    _sessions.remove(playerId);
    try {
      await _channel.invokeMethod(
        'dispose',
        <String, dynamic>{'playerId': playerId},
      );
    } finally {
      state.value = RenderState.idle;
    }
  }
}
