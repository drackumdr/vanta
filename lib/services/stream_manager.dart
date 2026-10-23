import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../video/encryption/rtsp_decryption_proxy.dart';
import '../video/rtsp_session.dart';
import '../video/video_sink.dart';

/// Entrada activa de un stream reutilizable.
class ActiveStream {
  ActiveStream(
    this.cameraId,
    this.session,
    this.lastUrl, {
    this.proxy,
    this.verificationCode = '',
  });

  final String cameraId;
  final VideoSink session;
  String lastUrl;
  RtspDecryptionProxy? proxy;
  String verificationCode;
  int refCount = 1;
  int attempts = 0;
  Timer? retryTimer;
  bool disposed = false;

  String get effectivePlaybackUrl => proxy?.loopbackUrl ?? lastUrl;
}

/// Administra los streams de video visibles:
/// - Abre únicamente lo necesario.
/// - Reutiliza la sesión de una cámara al cambiar de layout (sin reconectar).
/// - Si el stream está cifrado, intercala RtspDecryptionProxy en loopback local.
/// - Reconecta con backoff exponencial + jitter, con límite de intentos.
class StreamManager extends ChangeNotifier {
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
  /// Idempotente: abre lo nuevo, reconfigura lo cambiado, cierra lo invisible.
  Future<void> sync(
    Map<String, String> desiredUrls, {
    Map<String, String>? verificationCodes,
  }) async {
    reconcile(desiredUrls.keys.toSet());
    for (final entry in desiredUrls.entries) {
      final code = verificationCodes?[entry.key] ?? '';
      final current = _active[entry.key];

      if (current != null && !current.disposed) {
        current.refCount = 1;
        current.attempts = 0;
        if (current.lastUrl != entry.value || current.verificationCode != code) {
          try {
            current.lastUrl = entry.value;
            current.verificationCode = code;
            await current.proxy?.dispose();
            current.proxy = null;

            if (code.isNotEmpty) {
              final proxy = RtspDecryptionProxy(
                targetUrl: entry.value,
                verificationCode: code,
              );
              await proxy.start();
              current.proxy = proxy;
            }

            await current.session.open(current.effectivePlaybackUrl);
          } on Exception {
            // Se mantiene el último stream conocido.
          }
        }
      } else {
        try {
          RtspDecryptionProxy? proxy;
          var playUrl = entry.value;

          if (code.isNotEmpty) {
            proxy = RtspDecryptionProxy(
              targetUrl: entry.value,
              verificationCode: code,
            );
            await proxy.start();
            playUrl = proxy.loopbackUrl;
          }

          final session = await createVideoSink(playUrl);
          final stream = ActiveStream(
            entry.key,
            session,
            entry.value,
            proxy: proxy,
            verificationCode: code,
          );
          _active[entry.key] = stream;
          _watch(stream);
        } catch (_) {
          // Si el canal nativo falla al crear, se reintenta en el próximo sync.
        }
      }
    }
    notifyListeners();
  }

  /// Adquiere (o reutiliza) el stream de una cámara. Si [url] cambió
  /// (p. ej. sub→main), reconfigura la sesión existente en caliente.
  Future<VideoSink> acquire({
    required String cameraId,
    required String url,
    String verificationCode = '',
  }) async {
    var entry = _active[cameraId];
    if (entry != null && !entry.disposed) {
      entry.refCount++;
      entry.attempts = 0;
      if (entry.lastUrl != url || entry.verificationCode != verificationCode) {
        try {
          entry.lastUrl = url;
          entry.verificationCode = verificationCode;
          await entry.proxy?.dispose();
          entry.proxy = null;

          if (verificationCode.isNotEmpty) {
            final proxy = RtspDecryptionProxy(
              targetUrl: url,
              verificationCode: verificationCode,
            );
            await proxy.start();
            entry.proxy = proxy;
          }

          await entry.session.open(entry.effectivePlaybackUrl);
        } on Exception {
          // La sesión conserva el último stream conocido.
        }
      }
      return entry.session;
    }

    RtspDecryptionProxy? proxy;
    var playUrl = url;
    if (verificationCode.isNotEmpty) {
      proxy = RtspDecryptionProxy(
        targetUrl: url,
        verificationCode: verificationCode,
      );
      await proxy.start();
      playUrl = proxy.loopbackUrl;
    }

    final session = await createVideoSink(playUrl);
    entry = ActiveStream(
      cameraId,
      session,
      url,
      proxy: proxy,
      verificationCode: verificationCode,
    );
    _active[cameraId] = entry;
    _watch(entry);
    notifyListeners();
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

    final base = math.min(
      500 * math.pow(2, entry.attempts),
      maxReconnectDelay.inMilliseconds,
    ).toInt();
    final jitter = math.Random().nextInt(250);
    entry.attempts++;
    entry.retryTimer = Timer(Duration(milliseconds: base + jitter), () async {
      if (entry.disposed || !_active.containsKey(entry.cameraId)) return;
      try {
        await entry.session.open(entry.effectivePlaybackUrl);
      } on Exception {
        _scheduleReconnect(entry);
      }
    });
  }

  void _close(ActiveStream entry) {
    entry.disposed = true;
    entry.retryTimer?.cancel();
    _active.remove(entry.cameraId);
    entry.proxy?.dispose();
    entry.session.dispose();
    notifyListeners();
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