import 'dart:typed_data';

/// Representación y parser de paquetes RTP (RFC 3550).
class RtpPacket {
  final int version;
  final bool padding;
  final bool extension;
  final int csrcCount;
  final bool marker;
  final int payloadType;
  final int sequenceNumber;
  final int timestamp;
  final int ssrc;
  final int headerLength;
  final Uint8List payload;

  RtpPacket({
    required this.version,
    required this.padding,
    required this.extension,
    required this.csrcCount,
    required this.marker,
    required this.payloadType,
    required this.sequenceNumber,
    required this.timestamp,
    required this.ssrc,
    required this.headerLength,
    required this.payload,
  });

  /// Parsea un paquete RTP a partir de [bytes].
  /// Devuelve null si el buffer es menor a 12 bytes o el número de versión no es 2.
  static RtpPacket? parse(Uint8List bytes, [int offset = 0, int? length]) {
    final len = length ?? (bytes.length - offset);
    if (len < 12) return null;

    final b0 = bytes[offset];
    final version = (b0 >>> 6) & 0x03;
    if (version != 2) return null;

    final padding = ((b0 >>> 5) & 0x01) == 1;
    final extension = ((b0 >>> 4) & 0x01) == 1;
    final csrcCount = b0 & 0x0F;

    final b1 = bytes[offset + 1];
    final marker = ((b1 >>> 7) & 0x01) == 1;
    final payloadType = b1 & 0x7F;

    final seq = (bytes[offset + 2] << 8) | bytes[offset + 3];
    final timestamp = (bytes[offset + 4] << 24) |
        (bytes[offset + 5] << 16) |
        (bytes[offset + 6] << 8) |
        bytes[offset + 7];
    final ssrc = (bytes[offset + 8] << 24) |
        (bytes[offset + 9] << 16) |
        (bytes[offset + 10] << 8) |
        bytes[offset + 11];

    var hdrLen = 12 + (csrcCount * 4);
    if (len < hdrLen) return null;

    if (extension) {
      if (len < hdrLen + 4) return null;
      final extWords = (bytes[offset + hdrLen + 2] << 8) | bytes[offset + hdrLen + 3];
      hdrLen += 4 + (extWords * 4);
      if (len < hdrLen) return null;
    }

    var padLen = 0;
    if (padding && len > hdrLen) {
      padLen = bytes[offset + len - 1];
      if (hdrLen + padLen > len) return null;
    }

    final payloadLen = len - hdrLen - padLen;
    final payload = Uint8List.sublistView(bytes, offset + hdrLen, offset + hdrLen + payloadLen);

    return RtpPacket(
      version: version,
      padding: padding,
      extension: extension,
      csrcCount: csrcCount,
      marker: marker,
      payloadType: payloadType,
      sequenceNumber: seq,
      timestamp: timestamp,
      ssrc: ssrc,
      headerLength: hdrLen,
      payload: payload,
    );
  }

  /// Serializa el paquete RTP con un nuevo [newPayload] opcional y flag [newMarker].
  Uint8List serialize({Uint8List? newPayload, bool? newMarker, int? newSeq}) {
    final p = newPayload ?? payload;
    final m = newMarker ?? marker;
    final s = newSeq ?? sequenceNumber;

    final out = Uint8List(12 + p.length);
    out[0] = 0x80; // V=2, P=0, X=0, CC=0
    out[1] = ((m ? 1 : 0) << 7) | (payloadType & 0x7F);
    out[2] = (s >>> 8) & 0xFF;
    out[3] = s & 0xFF;
    out[4] = (timestamp >>> 24) & 0xFF;
    out[5] = (timestamp >>> 16) & 0xFF;
    out[6] = (timestamp >>> 8) & 0xFF;
    out[7] = timestamp & 0xFF;
    out[8] = (ssrc >>> 24) & 0xFF;
    out[9] = (ssrc >>> 16) & 0xFF;
    out[10] = (ssrc >>> 8) & 0xFF;
    out[11] = ssrc & 0xFF;

    out.setRange(12, 12 + p.length, p);
    return out;
  }
}

/// Reensamblador de fragmentos FU-A (RFC 6184 Tipo 28).
class FuAReassembler {
  int? _activeTimestamp;
  int? _expectedSeq;
  int _originalNalHeader = 0;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  /// Alimenta un paquete RTP con payload FU-A.
  ///
  /// Si el fragmento completa un NAL unit (`E == 1`), devuelve el NAL unit reconstruido
  /// (con su byte de cabecera original en `[0]`).
  /// Si es un fragmento intermedio, devuelve `null`.
  /// Si detecta discontinuidad de secuencia, descarta el fragmento anterior y comienza de nuevo.
  Uint8List? feedFragment(RtpPacket packet) {
    final payload = packet.payload;
    if (payload.length < 2) return null;

    final fuIndicator = payload[0];
    final fuHeader = payload[1];

    final isStart = (fuHeader & 0x80) != 0;
    final isEnd = (fuHeader & 0x40) != 0;
    final nalType = fuHeader & 0x1F;

    if (isStart) {
      _builder.clear();
      _activeTimestamp = packet.timestamp;
      _expectedSeq = (packet.sequenceNumber + 1) & 0xFFFF;
      _originalNalHeader = (fuIndicator & 0xE0) | nalType;
      _builder.addByte(_originalNalHeader);
      _builder.add(Uint8List.sublistView(payload, 2));
      if (isEnd) {
        final completed = _builder.takeBytes();
        _activeTimestamp = null;
        _expectedSeq = null;
        return completed;
      }
      return null;
    }

    // Verificar coherencia de secuencia y timestamp
    if (_activeTimestamp == null ||
        packet.timestamp != _activeTimestamp ||
        packet.sequenceNumber != _expectedSeq) {
      _builder.clear();
      _activeTimestamp = null;
      _expectedSeq = null;
      return null;
    }

    _expectedSeq = (packet.sequenceNumber + 1) & 0xFFFF;
    _builder.add(Uint8List.sublistView(payload, 2));

    if (isEnd) {
      final completed = _builder.takeBytes();
      _activeTimestamp = null;
      _expectedSeq = null;
      return completed;
    }

    return null;
  }
}

/// Fragmentador de NAL units a paquetes FU-A (RFC 6184).
class FuAFragmenter {
  /// Tamaño máximo de payload por paquete RTP (MTU segura para Ethernet/Wi-Fi).
  static const int defaultMaxPayloadSize = 1400;

  /// Fragmenta un NAL unit completo [nalu] en una lista de paquetes RTP FU-A.
  /// Usa [basePacket] como plantilla para timestamp, SSRC y payloadType.
  static List<Uint8List> fragmentNalu({
    required Uint8List nalu,
    required RtpPacket basePacket,
    required int startSeq,
    int maxPayloadSize = defaultMaxPayloadSize,
  }) {
    if (nalu.length <= 1) return [];

    final originalHeader = nalu[0];
    final nri = originalHeader & 0x60;
    final nalType = originalHeader & 0x1F;
    final fuIndicator = nri | 28; // FU-A type 28

    final data = Uint8List.sublistView(nalu, 1);
    final totalDataLen = data.length;
    final packets = <Uint8List>[];

    var offset = 0;
    var seq = startSeq;

    while (offset < totalDataLen) {
      final remaining = totalDataLen - offset;
      final chunkSize = remaining > maxPayloadSize ? maxPayloadSize : remaining;
      final isStart = offset == 0;
      final isEnd = (offset + chunkSize) == totalDataLen;

      final fuHeader = ((isStart ? 1 : 0) << 7) |
          ((isEnd ? 1 : 0) << 6) |
          (nalType & 0x1F);

      final chunkPayload = Uint8List(2 + chunkSize);
      chunkPayload[0] = fuIndicator;
      chunkPayload[1] = fuHeader;
      chunkPayload.setRange(2, 2 + chunkSize, data, offset);

      final serialized = basePacket.serialize(
        newPayload: chunkPayload,
        newMarker: isEnd,
        newSeq: seq & 0xFFFF,
      );

      packets.add(serialized);
      offset += chunkSize;
      seq++;
    }

    return packets;
  }
}
