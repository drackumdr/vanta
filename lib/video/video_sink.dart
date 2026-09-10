import 'dart:io';

import 'package:flutter/foundation.dart';

import 'desktop_session.dart';
import 'rtsp_session.dart';

/// Interfaz común de reproducción de video.
/// Android: Media3/ExoPlayer (plugins nativos). Desktop: media_kit/libmpv.
/// La UI, el StreamManager y los servicios solo dependen de esta abstracción.
abstract class VideoSink {
  ValueNotifier<RenderState> get state;
  ValueNotifier<String?> get error;
  bool get isSubstream;

  Future<void> open(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> setMuted(bool muted);
  Future<void> dispose();
}

/// Crea la sesión de video adecuada para la plataforma actual.
Future<VideoSink> createVideoSink(String url) async {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    return RtspSession.create(url);
  }
  return DesktopVideoSession.create(url);
}
