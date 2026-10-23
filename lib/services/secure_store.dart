import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credenciales de dispositivos.
/// Android/Windows: almacenamiento seguro nativo (Keystore/DPAPI).
/// Linux: intenta libsecret; si el entorno no tiene keyring, cae a
/// SharedPreferences (fallback pragmático para escritorio local).
class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _key(String deviceId) => 'dev_pwd_$deviceId';
  String _fallbackKey(String deviceId) => 'dev_pwd_fallback_$deviceId';

  Future<String?> readPassword(String deviceId) async {
    try {
      final v = await _storage.read(key: _key(deviceId));
      if (v != null) return v;
    } catch (_) {
      // El almacenamiento seguro no está disponible; se usa el fallback.
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fallbackKey(deviceId));
  }

  Future<void> writePassword(String deviceId, String password) async {
    if (password.isEmpty) return;
    try {
      await _storage.write(key: _key(deviceId), value: password);
      // Se limpia el fallback previo si hubiera.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_fallbackKey(deviceId));
      return;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fallbackKey(deviceId), password);
    }
  }

  Future<void> deletePassword(String deviceId) async {
    try {
      await _storage.delete(key: _key(deviceId));
    } catch (_) {
      // ignorar
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fallbackKey(deviceId));
  }

  String _codeKey(String deviceId) => 'dev_vcode_$deviceId';
  // ponytail: Sin backend seguro nativo (ej. Linux sin libsecret/keyring), el código de verificación
  // se retiene únicamente en memoria durante la sesión activa para evitar persistir claves criptográficas
  // en texto plano. Upgrade: integrar SecretService directo o archivo local cifrado con DPAPI/clave de host.
  final Map<String, String> _inMemoryVCodeCache = {};

  Future<String?> readVerificationCode(String deviceId) async {
    try {
      final v = await _storage.read(key: _codeKey(deviceId));
      if (v != null) return v;
    } catch (_) {}
    return _inMemoryVCodeCache[deviceId];
  }

  Future<void> writeVerificationCode(String deviceId, String code) async {
    if (code.isEmpty) {
      await deleteVerificationCode(deviceId);
      return;
    }
    _inMemoryVCodeCache[deviceId] = code;
    try {
      await _storage.write(key: _codeKey(deviceId), value: code);
      // Limpiar cualquier residuo de versiones previas en SharedPreferences si existiera
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('dev_vcode_fallback_$deviceId');
    } catch (_) {
      // Si el almacenamiento seguro nativo no está disponible, permanece en memoria durante la sesión
    }
  }

  Future<void> deleteVerificationCode(String deviceId) async {
    _inMemoryVCodeCache.remove(deviceId);
    try {
      await _storage.delete(key: _codeKey(deviceId));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dev_vcode_fallback_$deviceId');
  }
}