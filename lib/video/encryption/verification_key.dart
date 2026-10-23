import 'dart:convert';
import 'dart:typed_data';

/// Manejo y derivación de la clave de verificación para cifrado de flujo Hikvision/EZVIZ.
///
/// La clave simétrica para AES-128 se deriva aplicando zero-padding a 16 bytes sobre
/// el código de verificación alfanumérico configurado en el grabador (6 a 12 caracteres ASCII).
class VerificationKey {
  final Uint8List bytes;

  VerificationKey._(this.bytes);

  /// Deriva una [VerificationKey] de 16 bytes a partir del [code] de verificación.
  ///
  /// Lanza [ArgumentError] si el código está vacío o excede 16 bytes.
  factory VerificationKey.fromCode(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, 'code', 'El código de verificación no puede estar vacío');
    }
    final asciiBytes = ascii.encode(trimmed);
    if (asciiBytes.length > 16) {
      throw ArgumentError.value(
        code,
        'code',
        'El código de verificación excede los 16 bytes permitidos',
      );
    }
    final keyBytes = Uint8List(16);
    keyBytes.setRange(0, asciiBytes.length, asciiBytes);
    return VerificationKey._(keyBytes);
  }

  /// Crea una [VerificationKey] directa a partir de 16 bytes crudos.
  factory VerificationKey.fromBytes(List<int> rawBytes) {
    if (rawBytes.length != 16) {
      throw ArgumentError('La clave AES-128 debe tener exactamente 16 bytes');
    }
    return VerificationKey._(Uint8List.fromList(rawBytes));
  }

  /// Valida si un código tiene formato admisible para grabadores Hikvision (6 a 12 caracteres ASCII imprimibles).
  static bool isValidCode(String? code) {
    if (code == null) return false;
    final trimmed = code.trim();
    if (trimmed.length < 6 || trimmed.length > 12) return false;
    for (var i = 0; i < trimmed.length; i++) {
      final c = trimmed.codeUnitAt(i);
      if (c < 0x21 || c > 0x7E) return false; // Solo ASCII imprimible sin espacios
    }
    return true;
  }
}
