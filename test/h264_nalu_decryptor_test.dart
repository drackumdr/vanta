import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanta/video/encryption/h264_nalu_decryptor.dart';

void main() {
  group('H264NaluDecryptor', () {
    test('findStartCodes detects 3-byte and 4-byte prefixes', () {
      final stream = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x01, 0x67, 0x42, // start at 0 (len 4)
        0x00, 0x00, 0x01, 0x68, 0xCE,       // start at 6 (len 3)
        0x00, 0x00, 0x00, 0x01, 0x65,       // start at 11 (len 4)
      ]);

      final starts = H264NaluDecryptor.findStartCodes(stream);
      expect(starts, equals([0, 6, 11]));
    });

    test('decryptAnnexB decrypts SPS (type 7) and preserves SEI (6), PPS (8), AUD (9)', () {
      final decryptor = H264NaluDecryptor.fromCode('DVRDTK');

      // SPS cifrado del DVR real: 00 00 00 01 + header 0x67 + 16 bytes cifrados + 4 bytes residuales
      final encSps = [
        0x00, 0x00, 0x00, 0x01, // start code
        0x67,                   // NALU header: type=7, refIdc=3
        0xa0, 0x0b, 0xa2, 0x46, 0x6c, 0x11, 0x49, 0xda,
        0x17, 0xc0, 0x06, 0xdf, 0x83, 0xf0, 0x87, 0x4e, // 16 bytes cifrados
        0xAA, 0xBB, 0xCC, 0xDD, // 4 bytes residuales sin cifrar
      ];

      // PPS en claro (tipo 8)
      final unencPps = [
        0x00, 0x00, 0x00, 0x01,
        0x68, 0xee, 0x3c, 0xb0,
      ];

      // SEI en claro (tipo 6) con datos arbitrarios que NO deben tocarse
      final unencSei = [
        0x00, 0x00, 0x00, 0x01,
        0x06, 0x05, 0xFF, 0xFF, 0x01, 0x02, 0x03, 0x04,
        0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C,
        0x0D, 0x0E, 0x0F, 0x10, // 20 bytes que si se descifraran erróneamente se corromperían
      ];

      // AUD en claro (tipo 9)
      final unencAud = [
        0x00, 0x00, 0x01,
        0x09, 0x10,
      ];

      final combinedStream = Uint8List.fromList([
        ...encSps,
        ...unencPps,
        ...unencSei,
        ...unencAud,
      ]);

      final decrypted = decryptor.decryptAnnexB(combinedStream);

      // 1. El SPS debe tener su header 0x67 intacto y los 16 bytes descifrados
      expect(decrypted.sublist(0, 4), equals([0x00, 0x00, 0x00, 0x01]));
      expect(decrypted[4], equals(0x67)); // header en claro
      expect(
        decrypted.sublist(5, 21),
        equals([
          0x67, 0x64, 0x00, 0x20, 0xac, 0x1b, 0x1a, 0x80,
          0xf0, 0x08, 0x9a, 0x10, 0x00, 0x00, 0xbb, 0x80,
        ]),
      );
      expect(decrypted.sublist(21, 25), equals([0xAA, 0xBB, 0xCC, 0xDD]));

      // 2. PPS intacto
      expect(decrypted.sublist(25, 33), equals(unencPps));

      // 3. SEI intacto (no corrompido)
      expect(decrypted.sublist(33, 57), equals(unencSei));

      // 4. AUD intacto
      expect(decrypted.sublist(57), equals(unencAud));
    });

    test('decryptNaluPayload decrypts single RTP NAL unit payload in place', () {
      final decryptor = H264NaluDecryptor.fromCode('DVRDTK');

      // NALU SPS sin código de inicio Annex B (como viene en paquete RTP single NALU)
      final naluPayload = Uint8List.fromList([
        0x67, // Header
        0xa0, 0x0b, 0xa2, 0x46, 0x6c, 0x11, 0x49, 0xda,
        0x17, 0xc0, 0x06, 0xdf, 0x83, 0xf0, 0x87, 0x4e, // Cifrado
        0x12, 0x34, // Residual
      ]);

      final dec = decryptor.decryptNaluPayload(naluPayload);
      expect(dec[0], equals(0x67)); // Header preservado
      expect(
        dec.sublist(1, 17),
        equals([
          0x67, 0x64, 0x00, 0x20, 0xac, 0x1b, 0x1a, 0x80,
          0xf0, 0x08, 0x9a, 0x10, 0x00, 0x00, 0xbb, 0x80,
        ]),
      );
      expect(dec.sublist(17), equals([0x12, 0x34]));
    });

    test('decryptAnnexB gracefully handles empty or short payloads', () {
      final decryptor = H264NaluDecryptor.fromCode('DVRDTK');

      final empty = Uint8List(0);
      expect(decryptor.decryptAnnexB(empty), equals(empty));

      final short = Uint8List.fromList([0x00, 0x00, 0x01]);
      expect(decryptor.decryptAnnexB(short), equals(short));

      final noStartCodes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78, 0x90]);
      expect(decryptor.decryptAnnexB(noStartCodes), equals(noStartCodes));
    });
  });
}
