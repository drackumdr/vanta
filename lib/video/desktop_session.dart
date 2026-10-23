import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
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
  bool _disposed = false;

  static Future<DesktopVideoSession> create(String url) async {
    final player = mk.Player(
      configuration: mk.PlayerConfiguration(title: 'VANTA'),
    );
    // ponytail: auto-safe activa decodificación por hardware si está disponible
    // y cae limpiamente a software si el formato o resolución es atípico.
    final controller = mkv.VideoController(
      player,
      configuration: const mkv.VideoControllerConfiguration(hwdec: 'auto-safe'),
    );
    // Live RTSP en Windows: forzar TCP para evitar pérdida de paquetes UDP,
    // usar perfil low-latency oficial de mpv y timeout de red controlado.
    final platform = player.platform;
    if (platform is mk.NativePlayer) {
      try {
        await platform.setProperty('rtsp-transport', 'tcp');
        await platform.setProperty('demuxer-lavf-o', 'rtsp_transport=tcp');
        await platform.setProperty('profile', 'low-latency');
        await platform.setProperty('network-timeout', '8');
      } catch (_) {
        // Seguir con defaults de media_kit si alguna propiedad no existe.
      }
    }
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
      _later(() {
        state.value = RenderState.error;
        error.value = _friendly(e);
      });
    });
    player.stream.playing.listen((p) {
      if (p) _ready();
    });
    player.stream.buffering.listen((b) {
      if (!b) {
        _ready();
      }
    });
    player.stream.completed.listen((c) {
      // En un flujo de videovigilancia en vivo, un completed indica desconexión del stream.
      if (c && state.value != RenderState.loading) {
        _later(() {
          state.value = RenderState.error;
          error.value = 'Transmisión finalizada';
        });
      }
    });
    player.stream.videoParams.listen((params) {
      final w = params.w;
      final h = params.h;
      if (w != null && h != null && w > 0 && h > 0) {
        // En DVRs (1080p Lite / 1080N a 960x1080 o 720N a 640x720),
        // el stream es anamórfico (w < h o perfiles HD) y debe forzarse a 16:9 en mpv.
        if (w < h || (w == 960 && h == 1080) || (w == 640 && h == 720) || (w >= 1280 || h >= 720)) {
          final platform = player.platform;
          if (platform is mk.NativePlayer) {
            try {
              platform.setProperty('video-aspect-override', '16:9');
            } catch (_) {}
          }
        }
      }
    });
  }

  void _ready() {
    if (error.value == null) _later(() => state.value = RenderState.ready);
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
    state.value = RenderState.loading;
    error.value = null;
    try {
      await player.stop();
      await player.open(mk.Media(url));
      await player.setVolume(_muted ? 0 : 100);
      await player.play();
    } catch (_) {
      _later(() {
        state.value = RenderState.error;
        error.value = 'No se pudo reproducir el video';
      });
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
    _disposed = true;
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
