import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/device_model.dart';
import '../services/dahua_service.dart';
import '../services/hikvision_service.dart';
import '../state/app_state.dart';
import 'tv/tv_focusable.dart';
import 'tv/tv_text_field.dart';

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
    text: widget.device?.name ?? '',
  );
  late final TextEditingController _host = TextEditingController(
    text: widget.device?.host ?? '',
  );
  late final TextEditingController _port = TextEditingController(
    text: (widget.device?.port ?? 80).toString(),
  );
  late final TextEditingController _rtspPort = TextEditingController(
    text: (widget.device?.rtspPort ?? 554).toString(),
  );
  late final TextEditingController _user = TextEditingController(
    text: widget.device?.username ?? '',
  );
  late final TextEditingController _pass = TextEditingController();
  late DeviceKind _kind = widget.device?.kind ?? DeviceKind.dvr;
  late DeviceBrand _brand = widget.device?.brand ?? DeviceBrand.hikvision;
  late bool _https = widget.device?.https ?? false;
  late bool _streamEncryption = widget.device?.streamEncryption ?? false;
  late final TextEditingController _verificationCode = TextEditingController(
    text: widget.device?.verificationCode ?? '',
  );
  bool _obscurePassword = true;

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  int? _discoveredChannels;
  List<int>? _discoveredChannelIds;
  bool _disablingEncryption = false;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _rtspPort.dispose();
    _user.dispose();
    _pass.dispose();
    _verificationCode.dispose();
    super.dispose();
  }

  Device _draft() {
    return Device(
      id: widget.device?.id ?? _uuid.v4(),
      name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
      kind: _kind,
      brand: _brand,
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 80,
      rtspPort: int.tryParse(_rtspPort.text.trim()) ?? 554,
      username: _user.text.trim(),
      password: _pass.text.isEmpty
          ? (widget.device?.password ?? '')
          : _pass.text,
      https: _https,
      streamEncryption: _streamEncryption,
      verificationCode: _verificationCode.text.trim(),
      channelCount: _discoveredChannels ?? widget.device?.channelCount ?? 0,
      channelIds:
          _discoveredChannelIds ?? widget.device?.channelIds ?? const [],
      createdAt: widget.device?.createdAt ?? DateTime.now(),
    );
  }

  Future<void> _testConnection() async {
    final draft = _draft();
    if (draft.host.isEmpty ||
        draft.username.isEmpty ||
        draft.password.isEmpty) {
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
    if (draft.brand == DeviceBrand.dahua) {
      try {
        final service = DahuaService(draft);
        final info = await service.fetchDeviceInfo();
        final channels = await service.fetchChannels();
        if (!mounted) return;
        setState(() {
          _testing = false;
          _testOk = true;
          _discoveredChannels = channels.isEmpty
              ? 0
              : channels.map((c) => c.id).reduce((a, b) => a > b ? a : b);
          _discoveredChannelIds =
              channels.map((c) => c.id).toList(growable: false);
          _testResult = 'Conectado · Dahua · modelo ${info.model}'
              '${info.serialNumber.isNotEmpty ? ' · SN: ${info.serialNumber}' : ''}'
              '\n$_discoveredChannels canales';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _testing = false;
          _testOk = false;
          _testResult = e.toString().replaceFirst('IsapiException:', '');
        });
      }
      return;
    }
    try {
      final service = HikvisionService(draft);
      final info = await service.fetchDeviceInfo();
      final channels = await service.fetchChannels();
      final enc = await service.checkStreamEncryption();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = true;
        _discoveredChannels = channels.isEmpty
            ? 0
            : channels.map((c) => c.id).reduce((a, b) => a > b ? a : b);
        _discoveredChannelIds = channels
            .map((c) => c.id)
            .toList(growable: false);
        switch (enc) {
          case StreamEncryptionActive(:final verificationCode):
            _streamEncryption = true;
            if (_verificationCode.text.isEmpty && verificationCode.isNotEmpty) {
              _verificationCode.text = verificationCode;
            }
          case StreamEncryptionDisabled():
            _streamEncryption = false;
          case StreamEncryptionUnsupported():
          case StreamEncryptionError():
            break;
        }
        final encWarning = switch (enc) {
          StreamEncryptionActive() =>
            '\n🔒 Cifrado de flujo activo en el DVR (requiere código de verificación o desactivarlo)',
          StreamEncryptionDisabled() => '',
          StreamEncryptionUnsupported() =>
            '\nℹ️ El dispositivo no reporta estado de cifrado vía ISAPI',
          StreamEncryptionError(:final message) =>
            '\n⚠️ No se pudo verificar cifrado ISAPI: $message',
        };
        _testResult =
            'Conectado · ${info.deviceName} · ${info.model}'
            '\nFW ${info.firmwareVersion} · $_discoveredChannels canales$encWarning';
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

  Future<void> _promptDisableEncryption() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF15171C),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFE5A83D),
              size: 22,
            ),
            SizedBox(width: 8),
            Text('Desactivar cifrado', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          '¿Deseas enviar comando ISAPI al grabador para desactivar el cifrado de flujo?\n\n'
          'Al desactivarlo, el video viajará sin cifrar en la red local y no requerirá código de verificación en VANTA.',
          style: TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(dialogCtx).pop(false),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text('Cancelar'),
            ),
          ),
          TvFocusable(
            borderRadius: BorderRadius.circular(8),
            backgroundColor: const Color(0xFF8B2519),
            focusedBackgroundColor: const Color(0xFFB53424),
            onTap: () => Navigator.of(dialogCtx).pop(true),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                'Desactivar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _disableEncryptionOnDevice();
    }
  }

  Future<void> _disableEncryptionOnDevice() async {
    setState(() => _disablingEncryption = true);
    try {
      final service = HikvisionService(_draft());
      final ok = await service.setStreamEncryption(false);
      if (!mounted) return;
      setState(() {
        _disablingEncryption = false;
        if (ok) {
          _streamEncryption = false;
          _testOk = true;
          _testResult = 'Cifrado desactivado exitosamente en el grabador.';
        } else {
          _testOk = false;
          _testResult =
              'El grabador no permitió desactivar el cifrado por ISAPI.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _disablingEncryption = false;
        _testOk = false;
        _testResult = 'Error al desactivar cifrado: $e';
      });
    }
  }

  Future<void> _save() async {
    final draft = _draft();
    if (draft.host.isEmpty ||
        draft.username.isEmpty ||
        draft.password.isEmpty) {
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
        title: Text(
          widget.device == null ? 'Nuevo dispositivo' : 'Editar dispositivo',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvTextField(
                controller: _name,
                labelText: 'Nombre',
                hintText: 'NVR Entrada principal',
              ),
              const SizedBox(height: 12),
              _TvChoiceSelector<DeviceKind>(
                title: 'Tipo de dispositivo',
                items: DeviceKind.values,
                labelOf: (k) => k.label,
                selected: _kind,
                onChanged: (k) => setState(() => _kind = k),
              ),
              const SizedBox(height: 12),
              _TvChoiceSelector<DeviceBrand>(
                title: 'Fabricante',
                items: DeviceBrand.values,
                labelOf: (b) => b.label,
                selected: _brand,
                onChanged: (b) => setState(() => _brand = b),
              ),
              const SizedBox(height: 12),
              TvTextField(
                controller: _host,
                keyboardType: TextInputType.number,
                labelText: 'Dirección IP',
                hintText: '192.168.1.24',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TvTextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      labelText: 'Puerto HTTP',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TvTextField(
                      controller: _rtspPort,
                      keyboardType: TextInputType.number,
                      labelText: 'Puerto RTSP',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TvTextField(controller: _user, labelText: 'Usuario'),
              const SizedBox(height: 12),
              TvTextField(
                controller: _pass,
                obscureText: _obscurePassword,
                labelText: 'Contraseña',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 8),
              TvFocusable(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _https = !_https),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text('HTTPS', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'Solo si tu dispositivo usa SSL (443)',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                  value: _https,
                  onChanged: (v) => setState(() => _https = v),
                ),
              ),
              if (_brand == DeviceBrand.hikvision) ...[
              const SizedBox(height: 6),
              TvFocusable(
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    setState(() => _streamEncryption = !_streamEncryption),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text(
                    'Cifrado de flujo (Hik-Connect / Stream Key)',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Actívalo si el grabador tiene habilitado "Stream Encryption"',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                  value: _streamEncryption,
                  onChanged: (v) => setState(() => _streamEncryption = v),
                ),
              ),
              if (_streamEncryption) ...[
                const SizedBox(height: 8),
                TvTextField(
                  controller: _verificationCode,
                  textCapitalization: TextCapitalization.characters,
                  labelText: 'Código de verificación / Clave de flujo',
                  hintText: 'Ej. DVRDTK (6 a 12 caracteres)',
                  helperText:
                      'Clave configurada en el menú Hik-Connect/EZVIZ del grabador',
                  prefixIcon: const Icon(Icons.key_outlined, size: 20),
                  suffixIcon: _verificationCode.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () =>
                              setState(() => _verificationCode.clear()),
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TvFocusable(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _disablingEncryption
                        ? null
                        : _promptDisableEncryption,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _disablingEncryption
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.lock_open_outlined,
                                  size: 16,
                                  color: Color(0xFF00E5FF),
                                ),
                          const SizedBox(width: 8),
                          const Text(
                            'Desactivar cifrado directamente en el grabador (ISAPI)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF00E5FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              ],
              const SizedBox(height: 10),
              if (_testResult != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testOk
                        ? const Color(0xFF0E2A1C)
                        : const Color(0xFF2A1210),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _testOk
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: _testOk
                            ? const Color(0xFF4CAF7D)
                            : const Color(0xFFE5533D),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testOk
                                ? const Color(0xFFAEDCBE)
                                : const Color(0xFFF0B3A9),
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
                    child: TvFocusable(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _testing ? null : _testConnection,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _testing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.wifi_tethering, size: 18),
                            const SizedBox(width: 8),
                            Text(_testing ? 'Probando…' : 'Probar conexión'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TvFocusable(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _save,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_outlined, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Guardar',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
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

/// Selector de opciones optimizado para D-Pad (Android TV).
class _TvChoiceSelector<T> extends StatelessWidget {
  const _TvChoiceSelector({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 6),
        Row(
          children: items.map((k) {
            final isSelected = k == selected;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TvFocusable(
                  onTap: () => onChanged(k),
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: isSelected
                      ? const Color(0xFF16324F)
                      : const Color(0xFF14171F),
                  focusedBackgroundColor: const Color(0xFF1F446C),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF00E5FF)
                            : Colors.white12,
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Text(
                      labelOf(k),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF00E5FF)
                            : Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
