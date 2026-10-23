import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../video/rtsp_session.dart';
import '../video/video_sink.dart';
import '../video/video_surface.dart';

/// Celda de video con overlays discretos (estado + nombre).
/// `session == null` => slot vacío.
class CameraTile extends StatefulWidget {
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
  State<CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<CameraTile> {
  Timer? _selectTimer;
  bool _longSelect = false;

  @override
  void dispose() {
    _selectTimer?.cancel();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.select) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (_selectTimer != null) return KeyEventResult.handled;
      _longSelect = false;
      _selectTimer = Timer(const Duration(milliseconds: 550), () {
        _selectTimer = null;
        _longSelect = true;
        widget.onLongPress?.call();
      });
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _selectTimer?.cancel();
      _selectTimer = null;
      if (!_longSelect) widget.onTap?.call();
      _longSelect = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
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
                VideoSurface(sink: session, fullscreen: widget.fullscreen),
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
                          const Icon(
                            Icons.videocam_off_outlined,
                            color: Colors.white38,
                            size: 28,
                          ),
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
                    child: Icon(
                      Icons.play_circle_outline,
                      color: Colors.white38,
                      size: 32,
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    return Focus(
      onKeyEvent: _handleKey,
      child: FocusableActionDetector(
        enabled: widget.onTap != null || widget.onLongPress != null,
        autofocus: widget.autofocus,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return AnimatedScale(
              scale: focused ? 1.025 : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.rounded ? 6 : 4),
                  border: Border.all(
                    color: focused
                        ? const Color(0xFF00E5FF)
                        : Colors.transparent,
                    width: focused ? 3.0 : 1.0,
                  ),
                  boxShadow: focused
                      ? const [
                          BoxShadow(
                            color: Color(0x6600E5FF),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.rounded ? 4 : 2),
                  child: GestureDetector(
                    onTap: widget.onTap,
                    onLongPress: widget.onLongPress,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        child,
                        if (widget.showLabel)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _Label(
                              name: widget.name,
                              isFocused: focused,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _emptySlot(BuildContext context) {
    return Container(
      color: const Color(0xFF111318),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.showVideocamIcon)
            const Icon(
              Icons.add_a_photo_outlined,
              color: Colors.white12,
              size: 30,
            ),
          if (widget.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.name,
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.name, this.isFocused = false});
  final String name;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isFocused ? const Color(0xCC000000) : null,
        gradient: isFocused
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
      ),
      alignment: Alignment.bottomLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFocused)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF00E5FF),
                shape: BoxShape.circle,
              ),
            ),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isFocused ? const Color(0xFF00E5FF) : Colors.white,
                fontSize: 12,
                fontWeight: isFocused ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
