import 'dart:async';
import 'dart:math' as math;

import '../video/rtsp_session.dart';
import '../video/video_sink.dart';

/// Entrada activa de un stream reutilizable.
class ActiveStream {
  ActiveStream(this.cameraId, this.session, this.lastUrl);

  final String cameraId;
  final VideoSink session;
  String lastUrl;
  int refCount = 1;
  int attempts = 0;
  Timer? retryTimer;
  bool disposed = false;
}

/// Administra los streams de video visibles:
/// - Abre únicamente lo necesario.
/// - Reutiliza la sesión de una cámara al cambiar de layout (sin reconectar).
/// - Reconecta con backoff exponencial + jitter, con límite de intentos.
class StreamManager {
  static const int maxReconnectAttempts = 12;
  static const Duration maxReconnectDelay = Duration(seconds: 30);

  final Map<String, ActiveStream> _active = {};

  int get activeCount => _active.length;

  StreamSnapshot? snapshot(String cameraId) {
    final s = _active[cameraId];
    if (s == null || s.disposed) return null;
    return StreamSnapshot(s.session, s.lastUrl);
  }

  bool isDesired(String cameraId) {
    final s = _active[cameraId];
    return s != null && !s.disposed && s.refCount > 0;
  }

  /// Sincroniza el conjunto deseado de streams (cameraId → url).
  /// Idempotente: abre lo nuevo, reconfigure lo cambiado, cierra lo invisible.
  Future<void> sync(Map<String, String> desiredUrls) async {
    reconcile(desiredUrls.keys.toSet());
    for (final entry in desiredUrls.entries) {
      final current = _active[entry.key];
      if (current != null && !current.disposed) {
        current.refCount = 1;
        current.attempts = 0;
        if (current.lastUrl != entry.value) {
          try {
            await current.session.open(entry.value);
            current.lastUrl = entry.value;
          } on Exception {
            // Se mantiene el último stream conocido.
          }
        }
      } else {
        try {
          final session = await createVideoSink(entry.value);
          final stream = ActiveStream(entry.key, session, entry.value);
          _active[entry.key] = stream;
          _watch(stream);
        } catch (_) {
          // Si el canal nativo falla al crear, se reintenta en el próximo sync.
        }
      }
    }
  }

  /// Adquiere (o reutiliza) el stream de una cámara. Si [url] cambió
  /// (p. ej. sub→main), reconfigura la sesión existente en caliente.
  Future<VideoSink> acquire({
    required String cameraId,
    required String url,
  }) async {
    var entry = _active[cameraId];
    if (entry != null && !entry.disposed) {
      entry.refCount++;
      entry.attempts = 0;
      if (entry.lastUrl != url) {
        try {
          await entry.session.open(url);
          entry.lastUrl = url;
        } on Exception {
          // La sesión conserva el último stream conocido.
        }
      }
      return entry.session;
    }

    final session = await createVideoSink(url);
    entry = ActiveStream(cameraId, session, url);
    _active[cameraId] = entry;
    _watch(entry);
    return session;
  }

  void release(String cameraId) {
    final entry = _active[cameraId];
    if (entry == null || entry.disposed) return;
    entry.refCount--;
    if (entry.refCount <= 0) _close(entry);
  }

  /// Cierra todo lo que no esté en [desired] (último paso de un cambio de vista).
  void reconcile(Set<String> desired) {
    for (final cameraId in _active.keys.toList()) {
      if (!desired.contains(cameraId)) _close(_active[cameraId]!);
    }
  }

  void _watch(ActiveStream entry) {
    entry.session.state.addListener(() {
      final s = entry.session.state.value;
      if (s == RenderState.ready) {
        entry.attempts = 0;
      } else if (s == RenderState.error) {
        _scheduleReconnect(entry);
      }
    });
  }

  void _scheduleReconnect(ActiveStream entry) {
    if (entry.disposed || !_active.containsKey(entry.cameraId)) return;
    if (entry.attempts >= maxReconnectAttempts) return;
    if (entry.retryTimer?.isActive ?? false) return;

    final base = math.min(500 * math.pow(2, entry.attempts), maxReconnectDelay.inMilliseconds).toInt();
    final jitter = math.Random().nextInt(250);
    entry.attempts++;
    entry.retryTimer = Timer(Duration(milliseconds: base + jitter), () async {
      if (entry.disposed || !_active.containsKey(entry.cameraId)) return;
      try {
        await entry.session.open(entry.lastUrl);
      } on Exception {
        _scheduleReconnect(entry);
      }
    });
  }

  void _close(ActiveStream entry) {
    entry.disposed = true;
    entry.retryTimer?.cancel();
    _active.remove(entry.cameraId);
    entry.session.dispose();
  }

  void disposeAll() {
    for (final entry in _active.values.toList()) {
      _close(entry);
    }
  }
}

class StreamSnapshot {
  const StreamSnapshot(this.session, this.url);
  final VideoSink session;
  final String url;
}