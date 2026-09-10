import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart' as wm;

import '../state/app_state.dart';
import '../widgets/camera_tile.dart';
import '../widgets/layout_bar.dart';
import 'camera_picker_dialog.dart';
import 'devices_page.dart';
import 'fullscreen_page.dart';
import 'views_sheet.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _videoWall = false;

  Future<void> _setVideoWall(bool value) async {
    setState(() => _videoWall = value);
    if (Platform.isWindows || Platform.isLinux) {
      await wm.windowManager.setFullScreen(value);
    }
  }

  Future<void> _toggleVideoWall() => _setVideoWall(!_videoWall);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_videoWall) _setVideoWall(false);
        },
        const SingleActivator(LogicalKeyboardKey.f11): _toggleVideoWall,
      },
      child: PopScope(
        canPop: !_videoWall,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _videoWall) _setVideoWall(false);
        },
        child: Scaffold(
          appBar: _videoWall ? null : AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('VANTA', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                Text('  SURVEILLANCE', style: TextStyle(color: Colors.white38, fontSize: 13, letterSpacing: 2.0)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.dashboard_customize_outlined),
                tooltip: 'Vistas',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  backgroundColor: const Color(0xFF15171C),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  builder: (_) => const ViewsSheet(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.dns_outlined),
                tooltip: 'Dispositivos',
                onPressed: () => Navigator.of(context).pushNamed(DevicesPage.route),
              ),
              IconButton(
                icon: const Icon(Icons.fullscreen),
                tooltip: 'Pared de video',
                onPressed: _toggleVideoWall,
              ),
            ],
          ),
          body: Column(
            children: [
              if (!_videoWall)
                LayoutBar(
                  gridSize: app.gridSize,
                  onSelected: app.setGridSize,
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
            const Icon(Icons.video_camera_front_outlined,
                color: Colors.white24, size: 64),
            const SizedBox(height: 14),
            const Text('Agrega tu primer dispositivo de videovigilancia',
                style: TextStyle(color: Colors.white54)),
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

    final hasCameras = app.allCameras.isNotEmpty;
    if (!hasCameras) {
      return const Center(
        child: Text('Sin cámaras disponibles',
            style: TextStyle(color: Colors.white38)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = app.gridSize.columns;
        const gap = 2.0;
        const pad = 2.0;
        // "Escenario" 16:9 que cabe completo en el área disponible.
        var stageW = constraints.maxWidth - pad * 2;
        var stageH = stageW * 9 / 16;
        final maxH = constraints.maxHeight - pad * 2;
        if (stageH > maxH) {
          stageH = maxH;
          stageW = stageH * 16 / 9;
        }
        return Center(
          child: SizedBox(
            width: stageW,
            height: stageH,
            child: GridView.builder(
              padding: const EdgeInsets.all(pad),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
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

  Future<void> _pickCamera(BuildContext context, AppState app, int position) async {
    final cam = await CameraPickerDialog.pick(context);
    if (cam != null && context.mounted) {
      app.assignCamera(position, cam.id);
    }
  }

  void _openFullscreen(BuildContext context, AppState app, String cameraId) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => FullscreenPage(cameraId: cameraId),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vista "$name" guardada')),
        );
      }
    }
  }
}
