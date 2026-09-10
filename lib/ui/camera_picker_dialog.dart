import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/camera_model.dart';
import '../models/device_model.dart';
import '../state/app_state.dart';

/// Selector de cámara por dispositivo (canales descubiertos).
class CameraPickerDialog extends StatefulWidget {
  const CameraPickerDialog({super.key});

  static Future<Camera?> pick(BuildContext context) {
    return showDialog<Camera>(
      context: context,
      builder: (_) => const CameraPickerDialog(),
    );
  }

  @override
  State<CameraPickerDialog> createState() => _CameraPickerDialogState();
}

class _CameraPickerDialogState extends State<CameraPickerDialog> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return AlertDialog(
      title: const Text('Seleccionar cámara'),
      backgroundColor: const Color(0xFF15171C),
      content: SizedBox(
        width: 440,
        child: app.devices.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sin dispositivos registrados.\nAgrega un DVR/NVR primero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final device in app.devices)
                      _DeviceSection(device: device),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cams = app.allCameras
        .where((c) => c.deviceId == device.id)
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                device.kind == DeviceKind.ipc
                    ? Icons.videocam_outlined
                    : Icons.dvr_outlined,
                size: 18,
                color: Colors.white54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  device.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${device.host}:${device.port}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (cams.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 26, bottom: 6),
              child: Text(
                'Sin canales disponibles',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cam in cams)
                  ActionChip(
                    avatar: const Icon(Icons.videocam_outlined,
                        size: 15,
                        color: Colors.white54),
                    label: Text(
                      cam.name,
                      style: const TextStyle(fontSize: 12),
                    ),
                    side: const BorderSide(color: Color(0xFF2A2F3A)),
                    backgroundColor: const Color(0xFF1D2026),
                    labelStyle: const TextStyle(color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(cam),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}