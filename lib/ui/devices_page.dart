import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_model.dart';
import '../services/dahua_service.dart';
import '../services/hikvision_service.dart';
import '../state/app_state.dart';
import 'device_form_page.dart';
import 'tv/tv_focusable.dart';

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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TvFocusable(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openForm(context),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.add),
              ),
            ),
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
                  TvFocusable(
                    onTap: () => _openForm(context),
                    borderRadius: BorderRadius.circular(10),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Agregar DVR / NVR',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
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
        onTap: () => Navigator.of(context).pushNamed(
          DeviceFormPage.route,
          arguments: d,
        ),
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
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                '${d.host}:${d.port} · ${d.kind.label}'
                '${d.channelCount > 0 ? ' · ${d.channelCount} canales' : ''}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (d.streamEncryption) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF332505),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFD97706), width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 11, color: Color(0xFFFBBF24)),
                    SizedBox(width: 3),
                    Text(
                      'Cifrado',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFFBBF24),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: TvFocusable(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _test(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.wifi_tethering, size: 20),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TvFocusable(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).pushNamed(
                  DeviceFormPage.route,
                  arguments: d,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.edit_outlined, size: 20),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TvFocusable(
                borderRadius: BorderRadius.circular(16),
                focusBorderColor: const Color(0xFFE5533D),
                onTap: () => _delete(context, app, d),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.delete_outline,
                      size: 20, color: Color(0xFFE5533D)),
                ),
              ),
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
      final info = widget.device.brand == DeviceBrand.dahua
          ? await DahuaService(widget.device).fetchDeviceInfo()
          : await HikvisionService(widget.device).fetchDeviceInfo();
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
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(ctx).pop(false),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 8),
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            focusBorderColor: const Color(0xFFE5533D),
            backgroundColor: const Color(0xFFE5533D),
            onTap: () => Navigator.of(ctx).pop(true),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text('Eliminar',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await app.removeDevice(d.id);
  }
}