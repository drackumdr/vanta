import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vanta/video/encryption/rtsp_decryption_proxy.dart';

void main() {
  group('RtspDecryptionProxy End-to-End Loopback', () {
    test('proxies RTSP commands and decrypts interleaved RTP frames', () async {
      // 1. Levantar servidor simulador de DVR
      final dvrServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final dvrPort = dvrServer.port;

      Socket? dvrToProxySocket;
      final dvrReceivedCompleter = Completer<String>();

      dvrServer.listen((sock) {
        dvrToProxySocket = sock;
        sock.listen((data) {
          final text = utf8.decode(data, allowMalformed: true);
          if (!dvrReceivedCompleter.isCompleted) {
            dvrReceivedCompleter.complete(text);
          }
        });
      });

      // 2. Iniciar el proxy apuntando al mock DVR
      final proxy = RtspDecryptionProxy(
        targetUrl: 'rtsp://127.0.0.1:$dvrPort/Streaming/Channels/101',
        verificationCode: 'DVRDTK',
      );
      await proxy.start();
      expect(proxy.port, greaterThan(0));
      expect(proxy.loopbackUrl, contains('rtsp://127.0.0.1:${proxy.port}/Streaming/Channels/101'));

      // 3. Conectar cliente (reproductor simulado) al proxy
      final clientSocket = await Socket.connect(InternetAddress.loopbackIPv4, proxy.port);
      final clientReceivedData = BytesBuilder();
      final clientReceivedCompleter = Completer<void>();
      final rtpReceivedCompleter = Completer<Uint8List>();
      final rtpBuffer = BytesBuilder();

      clientSocket.listen((data) {
        clientReceivedData.add(data);
        final bytesAll = clientReceivedData.toBytes();
        if (!clientReceivedCompleter.isCompleted && bytesAll.contains(10) && !bytesAll.contains(0x24)) {
          clientReceivedCompleter.complete();
        }
        if (bytesAll.contains(0x24)) {
          rtpBuffer.add(data);
          final rtpBytes = rtpBuffer.toBytes();
          final dollarIdx = rtpBytes.indexOf(0x24);
          if (dollarIdx != -1 && rtpBytes.length >= dollarIdx + 4) {
            final len = (rtpBytes[dollarIdx + 2] << 8) | rtpBytes[dollarIdx + 3];
            if (rtpBytes.length >= dollarIdx + 4 + len) {
              if (!rtpReceivedCompleter.isCompleted) {
                rtpReceivedCompleter.complete(Uint8List.sublistView(rtpBytes, dollarIdx, dollarIdx + 4 + len));
              }
            }
          }
        }
      });

      // 4. El reproductor envía OPTIONS
      clientSocket.write('OPTIONS rtsp://127.0.0.1:${proxy.port}/Streaming/Channels/101 RTSP/1.0\r\nCSeq: 1\r\n\r\n');
      await clientSocket.flush();

      // Verificar que el DVR recibió la petición con la URL reescrita
      final dvrReq = await dvrReceivedCompleter.future.timeout(const Duration(seconds: 3));
      expect(dvrReq, contains('OPTIONS'));
      expect(dvrReq, contains('127.0.0.1:$dvrPort'));

      // 5. El DVR responde 200 OK
      dvrToProxySocket!.write('RTSP/1.0 200 OK\r\nCSeq: 1\r\nPublic: OPTIONS, DESCRIBE, SETUP, PLAY\r\n\r\n');
      await dvrToProxySocket!.flush();

      await clientReceivedCompleter.future.timeout(const Duration(seconds: 3));
      final clientResp = utf8.decode(clientReceivedData.toBytes());
      expect(clientResp, contains('200 OK'));

      // 6. El DVR envía un frame RTP interleaved con SPS cifrado (canal 0)
      // RTP Header (12 bytes) + 0x67 + 16 bytes cifrados
      final rtpPayload = Uint8List(12 + 17);
      rtpPayload[0] = 0x80; rtpPayload[1] = 0x60;
      rtpPayload[2] = 0x00; rtpPayload[3] = 0x0A; // seq
      rtpPayload[4] = 0x00; rtpPayload[5] = 0x00; rtpPayload[6] = 0x01; rtpPayload[7] = 0x00; // ts
      rtpPayload[8] = 0x01; rtpPayload[9] = 0x02; rtpPayload[10] = 0x03; rtpPayload[11] = 0x04; // ssrc
      rtpPayload[12] = 0x67; // SPS header
      final encBytes = [
        0xa0, 0x0b, 0xa2, 0x46, 0x6c, 0x11, 0x49, 0xda,
        0x17, 0xc0, 0x06, 0xdf, 0x83, 0xf0, 0x87, 0x4e,
      ];
      rtpPayload.setRange(13, 29, encBytes);

      final interleavedFrame = BytesBuilder();
      interleavedFrame.addByte(0x24); // '$'
      interleavedFrame.addByte(0x00); // channel 0
      interleavedFrame.addByte((rtpPayload.length >>> 8) & 0xFF);
      interleavedFrame.addByte(rtpPayload.length & 0xFF);
      interleavedFrame.add(rtpPayload);

      clientReceivedData.clear();
      dvrToProxySocket!.add(interleavedFrame.toBytes());
      await dvrToProxySocket!.flush();

      final rtpDataReceived = await rtpReceivedCompleter.future.timeout(const Duration(seconds: 3));
      expect(rtpDataReceived[0], equals(0x24)); // '$'
      expect(rtpDataReceived[1], equals(0x00)); // channel 0

      // Extraer payload RTP
      final rtpStart = 4;
      final rtpParsed = rtpDataReceived.sublist(rtpStart);
      // El byte 12 es 0x67 (header de SPS)
      expect(rtpParsed[12], equals(0x67));
      // Los bytes 13..29 deben ser el bloque descifrado: 67 64 00 20 ac 1b 1a 80...
      expect(
        rtpParsed.sublist(13, 29),
        equals([
          0x67, 0x64, 0x00, 0x20, 0xac, 0x1b, 0x1a, 0x80,
          0xf0, 0x08, 0x9a, 0x10, 0x00, 0x00, 0xbb, 0x80,
        ]),
      );

      // 7. Cleanup
      await clientSocket.close();
      await proxy.dispose();
      await dvrServer.close();
    });
  });
}
