import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'rtsp_session.dart';
import 'video_sink.dart';

/// Motor de video de escritorio (Windows/Linux) basado en libmpv vía media_kit.
/// Mismo contrato de {VideoSink} que la sesión nativa de Android.
class DesktopVideoSession implements VideoSink {
  DesktopVideoSession._(this.player, this.controller);

  final mk.Player player;
  final mkv.VideoController controller;

  @override
  final ValueNotifier<RenderState> state = ValueNotifier(RenderState.loading);
  @override
  final ValueNotifier<String?> error = ValueNotifier(null);

  @override
  bool get isSubstream => _isSubstream;

  bool _muted = true;
  bool _isSubstream = false;

  static Future<DesktopVideoSession> create(String url) async {
    final player = mk.Player(
      configuration: mk.PlayerConfiguration(title: 'VANTA'),
    );
    final controller = mkv.VideoController(player);
    final session = DesktopVideoSession._(player, controller);
    session._wire();
    // El open transcurre en segundo plano: cada sesión llega a `ready`
    // cuando su buffering termina. No bloquear el sync del grid con 16 opens.
    session.open(url);
    return session;
  }

  void _wire() {
    player.stream.error.listen((e) {
      if (e.isEmpty) return;
      state.value = RenderState.error;
      error.value = _friendly(e);
    });
    player.stream.playing.listen((p) {
      if (p) _ready();
    });
    player.stream.buffering.listen((b) {
      if (b) {
        state.value = RenderState.loading;
      } else {
        _ready();
      }
    });
    player.stream.completed.listen((c) {
      // Un stop() (p. ej. re-open) también dispara `completed`; se ignora
      // mientras el stream está cargando.
      if (c && state.value != RenderState.loading) {
        state.value = RenderState.ended;
      }
    });
  }

  void _ready() {
    if (error.value == null) state.value = RenderState.ready;
  }

  @override
  Future<void> open(String url) async {
    _isSubstream = url.contains('/02');
    state.value = RenderState.loading;
    error.value = null;
    try {
      await player.stop();
      await player.open(mk.Media(url));
      await player.setVolume(_muted ? 0 : 100);
      await player.play();
    } catch (_) {
      state.value = RenderState.error;
      error.value = 'No se pudo reproducir el video';
    }
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> setMuted(bool muted) {
    _muted = muted;
    return player.setVolume(muted ? 0 : 100);
  }

  @override
  Future<void> dispose() async {
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {
      // El reproductor ya no está disponible.
    }
  }

  String _friendly(String raw) {
    final e = raw.toLowerCase();
    if (e.contains('timed out') || e.contains('timeout')) {
      return 'Tiempo de espera agotado';
    }
    if (e.contains('auth') ||
        e.contains('login') ||
        e.contains('401') ||
        e.contains('403')) {
      return 'El dispositivo rechazó la conexión';
    }
    if (e.contains('could not connect') ||
        e.contains('failed to connect') ||
        e.contains('econnrefused') ||
        e.contains('unreachable') ||
        e.contains('dns')) {
      return 'No se pudo conectar al dispositivo';
    }
    if (e.contains('unsupported') ||
        e.contains('unknown format') ||
        e.contains('codec')) {
      return 'Formato de video no soportado';
    }
    return raw.length > 120 ? raw.substring(0, 120) : raw;
  }
}
