import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/hikvision_service.dart';
import '../state/app_state.dart';
import 'device_form_page.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  static const route = '/devices';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Agregar dispositivo',
            onPressed: () => _openForm(context),
          ),
        ],
      ),
      body: app.devices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.dvr_outlined, color: Colors.white24, size: 56),
                  const SizedBox(height: 12),
                  const Text(
                    'Sin dispositivos registrados',
                    style: TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _openForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar DVR / NVR'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: app.devices.length,
              itemBuilder: (context, i) =>
                  _DeviceTile(device: app.devices[i]),
            ),
    );
  }

  void _openForm(BuildContext context, [Device? device]) {
    Navigator.of(context).pushNamed(DeviceFormPage.route, arguments: device);
  }
}

class _DeviceTile extends StatefulWidget {
  const _DeviceTile({required this.device});
  final Device device;

  @override
  State<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<_DeviceTile> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final d = widget.device;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1D2026),
          child: Icon(
            d.kind == DeviceKind.ipc
                ? Icons.videocam_outlined
                : Icons.dvr_outlined,
            size: 20,
          ),
        ),
        title: Text(
          d.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${d.host}:${d.port} · ${d.kind.label}'
          '${d.channelCount > 0 ? ' · ${d.channelCount} canales' : ''}',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_testing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.wifi_tethering, size: 20),
                tooltip: 'Probar conexión',
                onPressed: () => _test(context),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Editar',
              onPressed: () => Navigator.of(context).pushNamed(
                DeviceFormPage.route,
                arguments: d,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Eliminar',
              onPressed: () => _delete(context, app, d),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _test(BuildContext context) async {
    setState(() => _testing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = HikvisionService(widget.device);
      final info = await service.fetchDeviceInfo();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Conectado · ${info.deviceName} · ${info.model}'),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Fallo: ${e.toString().replaceFirst('IsapiException:', '')}'),
      ));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _delete(BuildContext context, AppState app, Device d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar dispositivo'),
        content: Text(
            '¿Eliminar "${d.name}"?\nSe quitarán sus cámaras de las vistas activas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5533D)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await app.removeDevice(d.id);
  }
}