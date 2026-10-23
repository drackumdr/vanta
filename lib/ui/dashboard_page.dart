import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart' as wm;

import '../state/app_state.dart';
import '../models/view_model.dart';
import '../widgets/camera_tile.dart';
import '../widgets/layout_bar.dart';
import 'camera_picker_dialog.dart';
import 'devices_page.dart';
import 'fullscreen_page.dart';
import 'recordings/recordings_page.dart';
import 'tv/tv_focusable.dart';
import 'views_sheet.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _videoWall = false;
  Timer? _inactivityTimer;
  static const Duration _inactivityDelay = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    if (Platform.isAndroid) {
      // En Android la app arranca como pared de video: solo video en pantalla
      // completa; cualquier tecla del DPAD la saca del modo.
      WidgetsBinding.instance.addPostFrameCallback((_) => _setVideoWall(true));
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (!_videoWall && Platform.isAndroid) {
      _inactivityTimer = Timer(_inactivityDelay, () {
        if (mounted && !_videoWall) {
          _setVideoWall(true);
        }
      });
    }
  }

  bool _isDpad(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter;

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    _resetInactivityTimer();
    final key = event.logicalKey;
    if (_videoWall && Platform.isAndroid && _isDpad(key)) {
      _setVideoWall(false);
      return true;
    }
    if (key == LogicalKeyboardKey.f11) {
      _toggleVideoWall();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && _videoWall) {
      _setVideoWall(false);
      return true;
    }
    return false;
  }

  Future<void> _setVideoWall(bool value) async {
    _inactivityTimer?.cancel();
    setState(() => _videoWall = value);
    if (!value) {
      _resetInactivityTimer();
    }
    if (Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } else if (Platform.isWindows || Platform.isLinux) {
      await wm.windowManager.setFullScreen(value);
    }
  }

  Future<void> _toggleVideoWall() async {
    if (Platform.isWindows || Platform.isLinux) {
      final isFull = await wm.windowManager.isFullScreen();
      _setVideoWall(!isFull);
    } else {
      _setVideoWall(!_videoWall);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return PopScope(
      canPop: !_videoWall,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _videoWall) _setVideoWall(false);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetInactivityTimer(),
        child: Scaffold(
        appBar: _videoWall
            ? null
            : AppBar(
                title: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'VANTA',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      '  SURVEILLANCE',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
                actions: [
                  _TvNavButton(
                    icon: Icons.dashboard_customize_outlined,
                    label: 'Vistas',
                    onTap: () => showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF15171C),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(14),
                        ),
                      ),
                      builder: (_) => const ViewsSheet(),
                    ),
                  ),
                  _TvNavButton(
                    icon: Icons.history_outlined,
                    label: 'Grabaciones',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RecordingsPage()),
                    ),
                  ),
                  _TvNavButton(
                    icon: Icons.dns_outlined,
                    label: 'Dispositivos',
                    onTap: () =>
                        Navigator.of(context).pushNamed(DevicesPage.route),
                  ),
                  _TvNavButton(
                    icon: Icons.fullscreen,
                    label: 'Pared TV',
                    onTap: _toggleVideoWall,
                  ),
                  const SizedBox(width: 12),
                ],
              ),
        body: Column(
          children: [
            if (!_videoWall)
              LayoutBar(
                gridSize: app.gridSize,
                onSelected: app.setGridSize,
                onShowAll: app.showAllCameras,
                mainStream: app.mainStreamInGrid,
                onStreamSelected: app.setMainStreamInGrid,
                onSaveView: () => _saveViewDialog(context, app),
              ),
            Expanded(child: _buildBody(context, app)),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildBody(BuildContext context, AppState app) {
    if (!app.loaded && app.loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white38),
      );
    }
    if (app.devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.video_camera_front_outlined,
              color: Colors.white24,
              size: 64,
            ),
            const SizedBox(height: 14),
            const Text(
              'Agrega tu primer dispositivo de videovigilancia',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(DevicesPage.route),
              icon: const Icon(Icons.add),
              label: const Text('Registrar dispositivo'),
            ),
          ],
        ),
      );
    }
    if (app.allCameras.isEmpty) {
      return const Center(
        child: Text(
          'Sin cámaras disponibles',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSingle = app.gridSize == GridSize.one;
        final gap = _videoWall ? 6.0 : 4.0;
        final pad = _videoWall ? (isSingle ? 0.0 : 12.0) : (isSingle ? 0.0 : 6.0);
        var stageW = constraints.maxWidth - pad * 2;
        var stageH = stageW * 9 / 16;
        final maxH = constraints.maxHeight - pad * 2;
        if (stageH > maxH) {
          stageH = maxH;
          stageW = stageH * 16 / 9;
        }
        if (isSingle) {
          return Center(
            child: SizedBox(
              width: stageW,
              height: stageH,
              child: _buildCell(context, app, 0),
            ),
          );
        }
        if (app.gridSize == GridSize.six) {
          // 3x3: cuadrante superior izquierdo (2x2) es una sola cámara;
          // el doble de ancho y alto. Las otras 5 (derecha + abajo) iguales.
          return Center(
            child: SizedBox(
              width: stageW,
              height: stageH,
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildCell(context, app, 0),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: _buildCell(context, app, 1)),
                              SizedBox(height: gap),
                              Expanded(child: _buildCell(context, app, 2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 3; i <= 5; i++) ...[
                          if (i > 3) SizedBox(width: gap),
                          Expanded(child: _buildCell(context, app, i)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Center(
          child: SizedBox(
            width: stageW,
            height: stageH,
            child: GridView.builder(
              padding: EdgeInsets.all(pad),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: app.gridSize.columns,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap,
                childAspectRatio: 16 / 9,
              ),
              itemCount: app.gridSize.count,
              itemBuilder: (context, i) => _buildCell(context, app, i),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCell(BuildContext context, AppState app, int position) {
    final cameraId = app.cells[position];
    if (cameraId == null) {
      return CameraTile(
        session: null,
        name: 'Posición ${position + 1}',
        autofocus: position == 0,
        onTap: () => _pickCamera(context, app, position),
        showVideocamIcon: false,
      );
    }
    final camera = app.cameraById(cameraId);
    if (camera == null) {
      return CameraTile(
        session: null,
        name: 'Cámara no encontrada',
        autofocus: position == 0,
        onTap: () => _pickCamera(context, app, position),
      );
    }
    return CameraTile(
      session: app.streams.snapshot(cameraId)?.session,
      name: camera.name,
      autofocus: position == 0,
      onTap: () => _openFullscreen(context, app, cameraId),
      onLongPress: () => _pickCamera(context, app, position),
    );
  }

  Future<void> _pickCamera(
    BuildContext context,
    AppState app,
    int position,
  ) async {
    final cam = await CameraPickerDialog.pick(context);
    if (cam != null && context.mounted) {
      app.assignCamera(position, cam.id);
    }
  }

  void _openFullscreen(BuildContext context, AppState app, String cameraId) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => FullscreenPage(cameraId: cameraId),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 160),
      ),
    );
  }

  Future<void> _saveViewDialog(BuildContext context, AppState app) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar vista'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre de la vista',
            hintText: 'Entrada principal',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await app.saveAsView(name);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Vista "$name" guardada')));
      }
    }
  }
}

class _TvNavButton extends StatelessWidget {
  const _TvNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.sizeOf(context).width >= 960;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Tooltip(
        message: label,
        child: TvFocusable(
          borderRadius: BorderRadius.circular(8),
          padding: EdgeInsets.symmetric(horizontal: isTv ? 10 : 8, vertical: 6),
          backgroundColor: const Color(0xFF1D2026),
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: const Color(0xFF00E5FF)),
              if (isTv) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
