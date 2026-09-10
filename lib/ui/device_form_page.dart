import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/device_model.dart';
import '../services/hikvision_service.dart';
import '../state/app_state.dart';

class DeviceFormPage extends StatefulWidget {
  const DeviceFormPage({super.key, this.device});

  static const route = '/device-form';
  final Device? device;

  @override
  State<DeviceFormPage> createState() => _DeviceFormPageState();
}

class _DeviceFormPageState extends State<DeviceFormPage> {
  static const _uuid = Uuid();

  late final TextEditingController _name = TextEditingController(
      text: widget.device?.name ?? '');
  late final TextEditingController _host =
      TextEditingController(text: widget.device?.host ?? '');
  late final TextEditingController _port = TextEditingController(
      text: (widget.device?.port ?? 80).toString());
  late final TextEditingController _rtspPort = TextEditingController(
      text: (widget.device?.rtspPort ?? 554).toString());
  late final TextEditingController _user =
      TextEditingController(text: widget.device?.username ?? '');
  late final TextEditingController _pass = TextEditingController();
  late DeviceKind _kind = widget.device?.kind ?? DeviceKind.dvr;
  late bool _https = widget.device?.https ?? false;
  bool _obscurePassword = true;

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  int? _discoveredChannels;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _rtspPort.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Device _draft() {
    return Device(
      id: widget.device?.id ?? _uuid.v4(),
      name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
      kind: _kind,
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 80,
      rtspPort: int.tryParse(_rtspPort.text.trim()) ?? 554,
      username: _user.text.trim(),
      password: _pass.text.isEmpty
          ? (widget.device?.password ?? '')
          : _pass.text,
      https: _https,
      channelCount: _discoveredChannels ?? widget.device?.channelCount ?? 0,
      createdAt: widget.device?.createdAt ?? DateTime.now(),
    );
  }

  Future<void> _testConnection() async {
    final draft = _draft();
    if (draft.host.isEmpty || draft.username.isEmpty || draft.password.isEmpty) {
      setState(() {
        _testResult = 'Completa IP, usuario y contraseña';
        _testOk = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final service = HikvisionService(draft);
      final info = await service.fetchDeviceInfo();
      final channels = await service.fetchChannels();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = true;
        _discoveredChannels =
            channels.isEmpty ? 0 : channels.map((c) => c.id).reduce((a, b) => a > b ? a : b);
        _testResult = 'Conectado · ${info.deviceName} · ${info.model}'
            '\nFW ${info.firmwareVersion} · $_discoveredChannels canales';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = false;
        _testResult = e.toString().replaceFirst('IsapiException:', '');
      });
    }
  }

  Future<void> _save() async {
    final draft = _draft();
    if (draft.host.isEmpty || draft.username.isEmpty || draft.password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa IP, usuario y contraseña')),
      );
      return;
    }
    await context.read<AppState>().saveDevice(draft);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device == null ? 'Nuevo dispositivo' : 'Editar dispositivo'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'NVR Entrada principal',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DeviceKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: DeviceKind.values
                    .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                    .toList(),
                onChanged: (k) => setState(() => _kind = k ?? DeviceKind.dvr),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _host,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Dirección IP',
                  hintText: '192.168.1.24',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Puerto HTTP'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _rtspPort,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Puerto RTSP'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _user,
                decoration: const InputDecoration(labelText: 'Usuario'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('HTTPS', style: TextStyle(fontSize: 14)),
                subtitle: const Text('Solo si tu dispositivo usa SSL (443)',
                    style: TextStyle(fontSize: 12, color: Colors.white38)),
                value: _https,
                onChanged: (v) => setState(() => _https = v),
              ),
              const SizedBox(height: 8),
              if (_testResult != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testOk ? const Color(0xFF0E2A1C) : const Color(0xFF2A1210),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _testOk ? Icons.check_circle_outline : Icons.error_outline,
                        color: _testOk ? const Color(0xFF4CAF7D) : const Color(0xFFE5533D),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testOk ? const Color(0xFFAEDCBE) : const Color(0xFFF0B3A9),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: Text(_testing ? 'Probando…' : 'Probar conexión'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}