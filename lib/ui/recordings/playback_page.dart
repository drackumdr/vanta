import 'package:flutter/material.dart';

import '../../video/rtsp_session.dart';
import '../../video/video_sink.dart';
import '../../widgets/camera_tile.dart';

/// Reproduce un segmento de grabación vía RTSP por ventana de tiempo.
class PlaybackPage extends StatefulWidget {
  const PlaybackPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage> {
  VideoSink? _session;
  bool _ready = false;
  String? _error;
  bool _controls = true;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    try {
      final session = await createVideoSink(widget.url);
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() => _session = session);
      session.state.addListener(_onState);
      session.error.addListener(_onState);
      _onState();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo reproducir el video');
      }
    }
  }

  void _onState() {
    final session = _session;
    if (session == null || !mounted) return;
    setState(() {
      _ready = session.state.value == RenderState.ready;
      _error = session.error.value;
    });
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controls = !_controls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (session != null)
              CameraTile(
                session: session,
                name: widget.title,
                showLabel: false,
                rounded: false,
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white38),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54)),
                ),
              ),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            _muted = !_muted;
                            _session?.setMuted(_muted);
                          }),
                          icon: Icon(
                            _muted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            _ready
                                ? Icons.play_arrow
                                : Icons.hourglass_top,
                            size: 14,
                            color: _ready ? Colors.white70 : Colors.white38,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _ready
                                ? 'Reproduciendo'
                                : _error != null
                                    ? 'Error'
                                    : 'Cargando',
                            style: TextStyle(
                                color: _ready
                                    ? Colors.white70
                                    : Colors.white38,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}