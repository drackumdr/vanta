import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanta/video/encryption/rtp_h264_packet.dart';
import 'package:vanta/video/encryption/rtp_stream_decryptor.dart';

void main() {
  group('RtpPacket & RFC 6184 Parsing', () {
    test('parses and serializes standard RTP packet header', () {
      final raw = Uint8List(12 + 4);
      raw[0] = 0x80; // V=2
      raw[1] = 0x60; // M=0, PT=96
      raw[2] = 0x12; raw[3] = 0x34; // seq = 0x1234 (4660)
      raw[4] = 0x00; raw[5] = 0x01; raw[6] = 0x02; raw[7] = 0x03; // timestamp = 66051
      raw[8] = 0xDE; raw[9] = 0xAD; raw[10] = 0xBE; raw[11] = 0xEF; // SSRC
      raw[12] = 0x67; raw[13] = 0x64; raw[14] = 0x00; raw[15] = 0x20; // payload

      final pkt = RtpPacket.parse(raw);
      expect(pkt, isNotNull);
      expect(pkt!.version, equals(2));
      expect(pkt.marker, isFalse);
      expect(pkt.payloadType, equals(96));
      expect(pkt.sequenceNumber, equals(4660));
      expect(pkt.timestamp, equals(66051));
      expect(pkt.ssrc, equals(0xDEADBEEF));
      expect(pkt.payload, equals([0x67, 0x64, 0x00, 0x20]));

      final reserialized = pkt.serialize();
      expect(reserialized, equals(raw));
    });

    test('RtpStreamDecryptor decrypts Single NAL Unit (SPS) in RTP packet', () {
      final decryptor = RtpStreamDecryptor.fromCode('DVRDTK');

      // RTP header (12 bytes) + Encrypted SPS payload (17 bytes)
      final raw = Uint8List(12 + 17);
      raw[0] = 0x80; raw[1] = 0x60;
      raw[2] = 0x00; raw[3] = 0x01; // seq = 1
      raw[4] = 0x00; raw[5] = 0x00; raw[6] = 0x10; raw[7] = 0x00; // ts
      raw[8] = 0x00; raw[9] = 0x00; raw[10] = 0x00; raw[11] = 0x01; // ssrc
      
      // Payload: NALU 7 (0x67) + 16 encrypted bytes
      raw[12] = 0x67;
      final encBytes = [
        0xa0, 0x0b, 0xa2, 0x46, 0x6c, 0x11, 0x49, 0xda,
        0x17, 0xc0, 0x06, 0xdf, 0x83, 0xf0, 0x87, 0x4e,
      ];
      raw.setRange(13, 29, encBytes);

      final outPackets = decryptor.processRtpPacket(raw);
      expect(outPackets.length, equals(1));

      final outPkt = RtpPacket.parse(outPackets.first)!;
      expect(outPkt.payload[0], equals(0x67)); // header preservado
      expect(
        outPkt.payload.sublist(1, 17),
        equals([
          0x67, 0x64, 0x00, 0x20, 0xac, 0x1b, 0x1a, 0x80,
          0xf0, 0x08, 0x9a, 0x10, 0x00, 0x00, 0xbb, 0x80,
        ]),
      );
    });

    test('RtpStreamDecryptor reassembles, decrypts, and re-fragments FU-A packets', () {
      final decryptor = RtpStreamDecryptor.fromCode('DVRDTK');

      // Creamos un NAL unit IDR slice (tipo 5, 0x65) con 32 bytes cifrados
      final nalu = Uint8List(1 + 32);
      nalu[0] = 0x65; // IDR Slice
      // Llenamos con 2 bloques cifrados de 16 bytes
      final encBlock = [
        0xa0, 0x0b, 0xa2, 0x46, 0x6c, 0x11, 0x49, 0xda,
        0x17, 0xc0, 0x06, 0xdf, 0x83, 0xf0, 0x87, 0x4e,
      ];
      nalu.setRange(1, 17, encBlock);
      nalu.setRange(17, 33, encBlock);

      // Fragmentamos el NALU en 2 paquetes FU-A con maxPayloadSize = 20
      final baseRtp = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        csrcCount: 0,
        marker: false,
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 90000,
        ssrc: 0x11223344,
        headerLength: 12,
        payload: Uint8List(0),
      );

      final fuPackets = FuAFragmenter.fragmentNalu(
        nalu: nalu,
        basePacket: baseRtp,
        startSeq: 100,
        maxPayloadSize: 20,
      );

      expect(fuPackets.length, equals(2));

      // Alimentamos el primer fragmento (Start)
      final out1 = decryptor.processRtpPacket(fuPackets[0]);
      expect(out1, isEmpty); // Aún no está completo

      // Alimentamos el segundo fragmento (End)
      final out2 = decryptor.processRtpPacket(fuPackets[1]);
      expect(out2.isNotEmpty, isTrue);

      // Reensamblamos los paquetes descifrados para verificar que el NALU final esté limpio
      final reassembler = FuAReassembler();
      Uint8List? finalDecryptedNalu;
      for (final p in out2) {
        final parsed = RtpPacket.parse(p)!;
        final res = reassembler.feedFragment(parsed);
        if (res != null) finalDecryptedNalu = res;
      }

      expect(finalDecryptedNalu, isNotNull);
      expect(finalDecryptedNalu![0], equals(0x65)); // IDR Slice preservado
      // Ambos bloques deben estar descifrados
      final expectedBlock = [
        0x67, 0x64, 0x00, 0x20, 0xac, 0x1b, 0x1a, 0x80,
        0xf0, 0x08, 0x9a, 0x10, 0x00, 0x00, 0xbb, 0x80,
      ];
      expect(finalDecryptedNalu.sublist(1, 17), equals(expectedBlock));
      expect(finalDecryptedNalu.sublist(17, 33), equals(expectedBlock));
    });

    test('RtpStreamDecryptor decrypts STAP-A aggregation packets', () {
      final decryptor = RtpStreamDecryptor.fromCode('DVRDTK');

      // STAP-A header (0x78 = Type 24, NRI=3)
      // NALU 1: SPS cifrado (17 bytes: 0x67 + 16 bytes cifrados)
      // NALU 2: PPS en claro (4 bytes: 0x68 0xEE 0x3C 0xB0)
      final stapPayload = BytesBuilder();
      stapPayload.addByte(0x78); // STAP-A header

      // NALU 1 length: 17
      stapPayload.addByte(0x00); stapPayload.addByte(0x11);
      stapPayload.addByte(0x67);
      stapPayload.add([
        0xa0, 0x0b, 0xa2, 0x46, 0x6c, 0x11, 0x49, 0xda,
        0x17, 0xc0, 0x06, 0xdf, 0x83, 0xf0, 0x87, 0x4e,
      ]);

      // NALU 2 length: 4
      stapPayload.addByte(0x00); stapPayload.addByte(0x04);
      stapPayload.add([0x68, 0xee, 0x3c, 0xb0]);

      final rawRtp = RtpPacket(
        version: 2,
        padding: false,
        extension: false,
        csrcCount: 0,
        marker: false,
        payloadType: 96,
        sequenceNumber: 50,
        timestamp: 1000,
        ssrc: 1,
        headerLength: 12,
        payload: stapPayload.toBytes(),
      ).serialize();

      final outPackets = decryptor.processRtpPacket(rawRtp);
      expect(outPackets.length, equals(1));

      final outPkt = RtpPacket.parse(outPackets.first)!;
      expect(outPkt.payload[0], equals(0x78)); // STAP-A header
      // Longitud NALU 1
      expect(outPkt.payload[1], equals(0x00));
      expect(outPkt.payload[2], equals(0x11));
      expect(outPkt.payload[3], equals(0x67));
      // Bloque descifrado
      expect(
        outPkt.payload.sublist(4, 20),
        equals([
          0x67, 0x64, 0x00, 0x20, 0xac, 0x1b, 0x1a, 0x80,
          0xf0, 0x08, 0x9a, 0x10, 0x00, 0x00, 0xbb, 0x80,
        ]),
      );
      // NALU 2 (PPS intacto)
      expect(outPkt.payload.sublist(20), equals([0x00, 0x04, 0x68, 0xee, 0x3c, 0xb0]));
    });
  });
}
