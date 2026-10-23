import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/camera_tile.dart';
import 'recordings/recordings_page.dart';
import 'tv/tv_focusable.dart';
import 'tv/tv_utils.dart';

class FullscreenPage extends StatefulWidget {
  const FullscreenPage({super.key, required this.cameraId});

  final String cameraId;

  @override
  State<FullscreenPage> createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<FullscreenPage> {
  late String _currentCameraId;
  bool _controls = true;
  Timer? _hideTimer;
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _currentCameraId = widget.cameraId;
    _app = context.read<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _app.setFocusCamera(_currentCameraId);
    });
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _controls) {
        setState(() => _controls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _nextCamera() {
    final cams = _app.allCameras;
    if (cams.isEmpty) return;
    final idx = cams.indexWhere((c) => c.id == _currentCameraId);
    final nextIdx = (idx + 1) % cams.length;
    setState(() {
      _currentCameraId = cams[nextIdx].id;
      _controls = true;
    });
    _app.setFocusCamera(_currentCameraId);
    _scheduleHide();
  }

  void _prevCamera() {
    final cams = _app.allCameras;
    if (cams.isEmpty) return;
    final idx = cams.indexWhere((c) => c.id == _currentCameraId);
    final prevIdx = (idx - 1 + cams.length) % cams.length;
    setState(() {
      _currentCameraId = cams[prevIdx].id;
      _controls = true;
    });
    _app.setFocusCamera(_currentCameraId);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _app.setFocusCamera(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final camera = app.cameraById(_currentCameraId);
    final session = app.streams.snapshot(_currentCameraId)?.session;
    final cams = app.allCameras;
    final currentIndex = cams.indexWhere((c) => c.id == _currentCameraId);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _prevCamera,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _nextCamera,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (!_controls) {
            setState(() => _controls = true);
            _scheduleHide();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (!_controls) {
            setState(() => _controls = true);
            _scheduleHide();
          }
        },
        const SingleActivator(LogicalKeyboardKey.select): _toggleControls,
        const SingleActivator(LogicalKeyboardKey.enter): _toggleControls,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraTile(
                session: session,
                name: camera?.name ?? '',
                showLabel: false,
                fullscreen: true,
              ),

              // Superposición de controles con margen de TV
              AnimatedOpacity(
                opacity: _controls ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: SafeArea(
                  child: Padding(
                    padding: TvUtils.overscanPadding,
                    child: Column(
                      children: [
                        // Barra superior: Botón volver y canal/posición
                        Row(
                          children: [
                            TvFocusable(
                              autofocus: _controls,
                              borderRadius: BorderRadius.circular(24),
                              padding: const EdgeInsets.all(8),
                              backgroundColor: Colors.black54,
                              onTap: () => Navigator.of(context).maybePop(),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back, color: Colors.white, size: 20),
                                  SizedBox(width: 6),
                                  Text(
                                    'Mosaico',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (cams.length > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(
                                  'Cámara ${currentIndex + 1} de ${cams.length} (◀ ▶ para cambiar)',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Spacer(),

                        // Barra inferior: Nombre de cámara y acceso directo a Grabaciones
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xDD101216),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00E5FF),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      camera?.name ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Canal  · Transmisión Principal en Vivo',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TvFocusable(
                                borderRadius: BorderRadius.circular(8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                backgroundColor: const Color(0xFF1E232E),
                                onTap: camera == null
                                    ? null
                                    : () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => RecordingsPage(
                                              deviceId: camera.deviceId,
                                              channel: camera.channel,
                                            ),
                                          ),
                                        );
                                      },
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.history, size: 18, color: Color(0xFF00E5FF)),
                                    SizedBox(width: 8),
                                    Text(
                                      'Ver Grabaciones',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
