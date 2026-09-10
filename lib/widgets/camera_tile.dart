import 'package:flutter/material.dart';

import '../video/rtsp_session.dart';
import '../video/video_sink.dart';
import '../video/video_surface.dart';

/// Celda de video con overlays discretos (estado + nombre).
/// `session == null` => slot vacío.
class CameraTile extends StatelessWidget {
  const CameraTile({
    super.key,
    required this.session,
    required this.name,
    this.onTap,
    this.onLongPress,
    this.showLabel = true,
    this.rounded = false,
    this.showVideocamIcon = true,
    this.fullscreen = false,
    this.autofocus = false,
  });

  final VideoSink? session;
  final String name;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showLabel;
  final bool rounded;
  final bool showVideocamIcon;
  final bool fullscreen;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    Widget child;

    if (session == null) {
      child = _emptySlot(context);
    } else {
      child = DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF060708)),
        child: AnimatedBuilder(
          animation: Listenable.merge([session.state, session.error]),
          builder: (context, _) {
            final state = session.state.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                VideoSurface(sink: session, fullscreen: fullscreen),
                if (state == RenderState.loading || state == RenderState.idle)
                  const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                if (state == RenderState.error)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_outlined,
                              color: Colors.white38, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            session.error.value ?? 'Sin señal',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (state == RenderState.ended)
                  const Center(
                    child: Icon(Icons.play_circle_outline,
                        color: Colors.white38, size: 32),
                  ),
              ],
            );
          },
        ),
      );
    }

    return FocusableActionDetector(
      enabled: onTap != null,
      autofocus: autofocus,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap?.call();
            return null;
          },
        ),
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return DecoratedBox(
            decoration: focused
                ? BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                  )
                : const BoxDecoration(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(rounded ? 6 : 0),
              child: GestureDetector(
                onTap: onTap,
                onLongPress: onLongPress,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    if (showLabel)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _Label(name: name),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptySlot(BuildContext context) {
    return Container(
      color: const Color(0xFF111318),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showVideocamIcon)
            const Icon(Icons.add_a_photo_outlined, color: Colors.white12, size: 30),
          if (name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                name,
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black54],
        ),
      ),
      alignment: Alignment.bottomLeft,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
