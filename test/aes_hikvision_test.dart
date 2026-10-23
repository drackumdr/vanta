import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanta/video/encryption/aes_hikvision.dart';
import 'package:vanta/video/encryption/verification_key.dart';

void main() {
  group('Aes128Hikvision', () {
    test('NIST FIPS 197 standard test vector', () {
      final keyBytes = Uint8List.fromList([
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
      ]);
      final plaintext = Uint8List.fromList([
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
      ]);
      final expectedCiphertext = Uint8List.fromList([
        0x69, 0xc4, 0xe0, 0xd8, 0x6a, 0x7b, 0x04, 0x30,
        0xd8, 0xcd, 0xb7, 0x80, 0x70, 0xb4, 0xc5, 0x5a,
      ]);

      final cipher = Aes128Hikvision.fromBytes(keyBytes);

      // Encriptación
      final enc = Uint8List(16);
      cipher.encryptBlock(plaintext, 0, enc, 0);
      expect(enc, equals(expectedCiphertext));

      // Desencriptación
      final dec = Uint8List(16);
      cipher.decryptBlock(enc, 0, dec, 0);
      expect(dec, equals(plaintext));
    });

    test('Real Hikvision DVR SPS decryption with verificationCode DVRDTK', () {
      final key = VerificationKey.fromCode('DVRDTK');
      expect(key.bytes, equals([
        0x44, 0x56, 0x52, 0x44, 0x54, 0x4b, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ]));

      final cipher = Aes128Hikvision(key);

      // Bloque cifrado capturado del stream real del DVR S08-TURBO-M1
      final encSps = Uint8List.fromList([
        0xa0, 0x0b, 0xa2, 0x46, 0x6c, 0x11, 0x49, 0xda,
        0x17, 0xc0, 0x06, 0xdf, 0x83, 0xf0, 0x87, 0x4e,
      ]);

      // Resultado descifrado: NALU 7 (0x67), Profile High (0x64), Level 3.2 (0x20)
      final expectedSps = Uint8List.fromList([
        0x67, 0x64, 0x00, 0x20, 0xac, 0x1b, 0x1a, 0x80,
        0xf0, 0x08, 0x9a, 0x10, 0x00, 0x00, 0xbb, 0x80,
      ]);

      final dec = Uint8List(16);
      cipher.decryptBlock(encSps, 0, dec, 0);
      expect(dec, equals(expectedSps));
    });

    test('VerificationKey input validation', () {
      expect(() => VerificationKey.fromCode(''), throwsArgumentError);
      expect(() => VerificationKey.fromCode('12345678901234567'), throwsArgumentError);
      expect(VerificationKey.isValidCode('DVRDTK'), isTrue);
      expect(VerificationKey.isValidCode('12345'), isFalse); // < 6
      expect(VerificationKey.isValidCode('1234567890123'), isFalse); // > 12
      expect(VerificationKey.isValidCode('ABC DEF'), isFalse); // contiene espacio
      expect(VerificationKey.isValidCode(null), isFalse);
    });
  });
}
