import 'dart:typed_data';

import 'aes_hikvision.dart';
import 'verification_key.dart';

/// Descifrador de NALUs H.264 para flujos de video con cifrado Hik-Connect / EZVIZ.
///
/// Especificación del cifrado Hikvision:
/// - Los paquetes H.264 transportan el byte de cabecera NALU siempre en claro (`nalType = byte & 0x1F`).
/// - **Únicamente** se cifran:
///   - Tipo 7: Sequence Parameter Set (SPS)
///   - Tipo 5: Coded slice of an IDR picture (I-frame)
///   - Tipo 1: Coded slice of a non-IDR picture (P/B-frame)
/// - Cualquier otro tipo pasa intacto:
///   - Tipo 8 (PPS), Tipo 6 (SEI), Tipo 9 (AUD), etc.
/// - El payload cifrado comienza inmediatamente después del byte de cabecera NALU (offset + 1).
/// - Se descifran bloques de 16 bytes con AES-128-ECB; los bytes residuales (< 16 bytes) no se alteran.
class H264NaluDecryptor {
  final Aes128Hikvision _cipher;

  H264NaluDecryptor(VerificationKey key) : _cipher = Aes128Hikvision(key);

  factory H264NaluDecryptor.fromCode(String code) {
    return H264NaluDecryptor(VerificationKey.fromCode(code));
  }

  /// Determina si un tipo de NALU es susceptible a cifrado en grabadores Hikvision.
  static bool isEncryptedType(int nalType) {
    return nalType == 1 || nalType == 5 || nalType == 7;
  }

  /// Descifra un NALU individual (sin código de inicio Annex B) tal como se recibe en RTP.
  ///
  /// Si el tipo de NALU es 1, 5 o 7, descifra in-place los bloques de 16 bytes a partir del byte 1.
  /// Para cualquier otro tipo (PPS 8, SEI 6, AUD 9), devuelve el buffer intacto.
  Uint8List decryptNaluPayload(Uint8List payload) {
    if (payload.length <= 1) return payload;
    final nalType = payload[0] & 0x1F;
    if (!isEncryptedType(nalType)) {
      return payload;
    }
    final encDataLen = payload.length - 1;
    final encLen = (encDataLen ~/ 16) * 16;
    if (encLen > 0) {
      _cipher.decryptBlocksInPlace(payload, 1, encLen);
    }
    return payload;
  }

  /// Descifra los NALUs presentes en un stream en formato Annex B ([bytes]).
  ///
  /// Devuelve un nuevo [Uint8List] con el flujo H.264 limpio listo para entregar al decodificador.
  Uint8List decryptAnnexB(Uint8List bytes) {
    if (bytes.length < 4) return bytes;

    final starts = findStartCodes(bytes);
    if (starts.isEmpty) {
      return bytes;
    }

    final out = Uint8List.fromList(bytes);

    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final nextStart = (i + 1 < starts.length) ? starts[i + 1] : bytes.length;

      final prefixLen = (start + 2 < bytes.length && bytes[start + 2] == 1) ? 3 : 4;
      final payloadStart = start + prefixLen;
      final payloadLen = nextStart - payloadStart;

      if (payloadLen <= 1) continue;

      final nalType = bytes[payloadStart] & 0x1F;

      // Filtrar estrictamente solo tipos cifrados (1, 5, 7)
      if (!isEncryptedType(nalType)) {
        continue;
      }

      // El cifrado comienza después del byte de header NALU (payloadStart + 1)
      final encDataLen = payloadLen - 1;
      final encLen = (encDataLen ~/ 16) * 16;
      if (encLen > 0) {
        _cipher.decryptBlocksInPlace(out, payloadStart + 1, encLen);
      }
    }

    return out;
  }

  /// Encuentra las posiciones de inicio de los códigos de sincronización Annex B (00 00 01 o 00 00 00 01).
  static List<int> findStartCodes(Uint8List bytes) {
    final starts = <int>[];
    var i = 0;
    final len = bytes.length;
    while (i < len - 2) {
      if (bytes[i] == 0 && bytes[i + 1] == 0) {
        if (bytes[i + 2] == 1) {
          starts.add(i);
          i += 3;
          continue;
        } else if (i < len - 3 && bytes[i + 2] == 0 && bytes[i + 3] == 1) {
          starts.add(i);
          i += 4;
          continue;
        }
      }
      i++;
    }
    return starts;
  }
}
