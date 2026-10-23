import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as mkv_controls;

import 'desktop_session.dart';
import 'rtsp_session.dart';
import 'video_sink.dart';

/// Renderiza el video de un [VideoSink] según la plataforma activa:
/// - Android/iOS: `Texture` del plugin nativo (Media3).
/// - Windows/Linux: widget `Video` de media_kit (libmpv).
class VideoSurface extends StatelessWidget {
  const VideoSurface({super.key, required this.sink, this.fullscreen = false});

  final VideoSink sink;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    if (sink is RtspSession) {
      final s = sink as RtspSession;
      if (s.textureId < 0) return const SizedBox.shrink();
      return ValueListenableBuilder<double?>(
        valueListenable: s.aspect,
        builder: (context, aspect, _) {
          final texture = Texture(
            textureId: s.textureId,
            filterQuality: FilterQuality.low,
          );
          if (!fullscreen) return texture;
          final ratio = (aspect != null && aspect > 0) ? aspect : 16 / 9;
          return Center(
            child: AspectRatio(aspectRatio: ratio, child: texture),
          );
        },
      );
    }
    if (sink is DesktopVideoSession) {
      final s = sink as DesktopVideoSession;
      return _DesktopVideoSurface(session: s, fullscreen: fullscreen);
    }
    return const SizedBox.shrink();
  }
}

class _DesktopVideoSurface extends StatelessWidget {
  const _DesktopVideoSurface({
    required this.session,
    required this.fullscreen,
  });

  final DesktopVideoSession session;
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<mk.VideoParams>(
      stream: session.player.stream.videoParams,
      initialData: session.player.state.videoParams,
      builder: (context, snapshot) {
        final params = snapshot.data;
        final aspect = _aspectOf(params);
        return mkv.Video(
          controller: session.controller,
          controls: mkv_controls.NoVideoControls,
          wakelock: false,
          fit: fullscreen ? BoxFit.contain : BoxFit.fill,
          aspectRatio: aspect,
        );
      },
    );
  }

  double? _aspectOf(mk.VideoParams? params) {
    if (params == null) return 16 / 9;
    final width = params.w;
    final height = params.h;
    // 960x1080 (1080 Lite / 1080N), 640x720 (720N) o cualquier stream
    // donde el ancho sea menor que el alto es anamórfico y debe estirarse a 16:9.
    if (width != null && height != null && width > 0 && height > 0) {
      if (width < height ||
          (width == 960 && height == 1080) ||
          (width == 640 && height == 720) ||
          (width >= 1280 || height >= 720)) {
        return 16 / 9;
      }
      return width / height;
    }
    final dw = params.dw;
    final dh = params.dh;
    if (dw != null && dh != null && dw > 0 && dh > 0) {
      if (dw < dh) return 16 / 9;
      return dw / dh;
    }
    final aspect = params.aspect;
    if (aspect != null && aspect.isFinite && aspect > 0) {
      if (aspect < 1.0) return 16 / 9;
      return aspect;
    }
    return 16 / 9;
  }
}
