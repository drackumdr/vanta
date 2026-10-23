import 'dart:typed_data';

import 'h264_nalu_decryptor.dart';
import 'rtp_h264_packet.dart';
import 'verification_key.dart';

/// Procesador y descifrador de flujos RTP H.264 (RFC 6184) para grabadores Hikvision.
///
/// Soporta de forma transparente:
/// 1. Single NAL Unit (tipos 1 a 23) - descifrado in-place.
/// 2. STAP-A (tipo 24) - agregación de múltiples NALUs.
/// 3. FU-A (tipo 28) - reensamblado, descifrado y re-fragmentación conforme a RFC 6184.
class RtpStreamDecryptor {
  final H264NaluDecryptor _decryptor;
  final FuAReassembler _fuAReassembler = FuAReassembler();
  final List<RtpPacket> _pendingFuPackets = [];

  RtpStreamDecryptor(VerificationKey key)
      : _decryptor = H264NaluDecryptor(key);

  factory RtpStreamDecryptor.fromCode(String code) {
    return RtpStreamDecryptor(VerificationKey.fromCode(code));
  }

  /// Procesa un paquete RTP crudo y devuelve una lista de paquetes RTP listos para ser entregados al reproductor.
  ///
  /// Para Single NAL Unit y STAP-A, devuelve una lista de 1 paquete.
  /// Para fragmentos FU-A intermedios, devuelve una lista vacía hasta completar el NALU.
  /// Al completar un NALU FU-A, lo descifra y devuelve la lista de paquetes FU-A limpios.
  List<Uint8List> processRtpPacket(Uint8List rawRtp) {
    final packet = RtpPacket.parse(rawRtp);
    if (packet == null || packet.payload.isEmpty) {
      return [rawRtp];
    }

    final payloadHeader = packet.payload[0];
    final nalType = payloadHeader & 0x1F;

    // 1. Single NAL Unit (tipos 1..23)
    if (nalType >= 1 && nalType <= 23) {
      if (H264NaluDecryptor.isEncryptedType(nalType)) {
        final decPayload = Uint8List.fromList(packet.payload);
        _decryptor.decryptNaluPayload(decPayload);
        return [packet.serialize(newPayload: decPayload)];
      }
      return [rawRtp];
    }

    // 2. STAP-A (tipo 24)
    if (nalType == 24) {
      return [_processStapA(packet)];
    }

    // 3. FU-A (tipo 28)
    if (nalType == 28) {
      return _processFuA(packet);
    }

    // Cualquier otro tipo (ej. RTP control o audio) pasa directo
    return [rawRtp];
  }

  Uint8List _processStapA(RtpPacket packet) {
    final payload = packet.payload;
    if (payload.length < 3) return packet.serialize();

    final outPayload = Uint8List.fromList(payload);
    var offset = 1; // saltar STAP-A NAL header

    while (offset + 2 <= outPayload.length) {
      final naluSize = (outPayload[offset] << 8) | outPayload[offset + 1];
      offset += 2;
      if (offset + naluSize > outPayload.length) break;

      final naluType = outPayload[offset] & 0x1F;
      if (H264NaluDecryptor.isEncryptedType(naluType)) {
        final naluView = Uint8List.sublistView(outPayload, offset, offset + naluSize);
        _decryptor.decryptNaluPayload(naluView);
      }
      offset += naluSize;
    }

    return packet.serialize(newPayload: outPayload);
  }

  List<Uint8List> _processFuA(RtpPacket packet) {
    final payload = packet.payload;
    if (payload.length < 2) return [packet.serialize()];

    final isStart = (payload[1] & 0x80) != 0;
    if (isStart) {
      _pendingFuPackets.clear();
    }

    _pendingFuPackets.add(packet);

    final nalu = _fuAReassembler.feedFragment(packet);
    if (nalu == null) {
      // Fragmento intermedio acumulado
      return const [];
    }

    // NALU completo reensamblado
    final nalType = nalu[0] & 0x1F;
    if (H264NaluDecryptor.isEncryptedType(nalType)) {
      _decryptor.decryptNaluPayload(nalu);
    }

    // Re-fragmentar el NALU descifrado conservando los números de secuencia y timestamps
    if (_pendingFuPackets.isEmpty) {
      return const [];
    }

    final base = _pendingFuPackets.first;
    final startSeq = base.sequenceNumber;

    final outputPackets = FuAFragmenter.fragmentNalu(
      nalu: nalu,
      basePacket: base,
      startSeq: startSeq,
    );

    _pendingFuPackets.clear();
    return outputPackets;
  }
}
