import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'rtp_stream_decryptor.dart';

/// Servidor proxy RTSP loopback local (127.0.0.1) que intercepta flujos RTSP TCP interleaved,
/// descifra los paquetes RTP H.264 usando [verificationCode] y entrega el flujo limpio
/// a reproductores estándar (Media3 / media_kit).
class RtspDecryptionProxy {
  final String targetUrl;
  final String verificationCode;

  ServerSocket? _server;
  int _port = 0;
  bool _closed = false;
  final List<Socket> _activeSockets = [];
  final Uri _targetUri;

  RtspDecryptionProxy({
    required this.targetUrl,
    required this.verificationCode,
  }) : _targetUri = Uri.parse(targetUrl);

  int get port => _port;

  /// URL loopback local para entregar al reproductor.
  String get loopbackUrl {
    final query = _targetUri.hasQuery ? '?${_targetUri.query}' : '';
    final path = _targetUri.path.isEmpty ? '/' : _targetUri.path;
    return 'rtsp://127.0.0.1:$_port$path$query';
  }

  /// Inicia el servidor TCP local en un puerto efímero.
  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handleIncomingClient, onError: (_) => dispose());
  }

  Future<void> _handleIncomingClient(Socket clientSocket) async {
    if (_closed) {
      clientSocket.destroy();
      return;
    }

    _activeSockets.add(clientSocket);

    Socket? serverSocket;
    try {
      final targetPort = _targetUri.hasPort ? _targetUri.port : 554;
      serverSocket = await Socket.connect(
        _targetUri.host,
        targetPort,
        timeout: const Duration(seconds: 5),
      );
      _activeSockets.add(serverSocket);
    } catch (_) {
      clientSocket.destroy();
      return;
    }

    final decryptor = RtpStreamDecryptor.fromCode(verificationCode);

    // Cliente (reproductor) -> Servidor (DVR)
    _pipeClientToServer(clientSocket, serverSocket);

    // Servidor (DVR con video cifrado) -> Cliente (reproductor con video limpio)
    _pipeServerToClient(serverSocket, clientSocket, decryptor);
  }

  void _pipeClientToServer(Socket client, Socket server) {
    final buffer = BytesBuilder(copy: false);

    client.listen(
      (data) {
        buffer.add(data);
        final bytes = buffer.toBytes();
        buffer.clear();

        var offset = 0;
        while (offset < bytes.length) {
          // Si es un paquete interleaved ($)
          if (bytes[offset] == 0x24) { // '$'
            if (offset + 4 > bytes.length) {
              buffer.add(Uint8List.sublistView(bytes, offset));
              break;
            }
            final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
            final frameLen = 4 + len;
            if (offset + frameLen > bytes.length) {
              buffer.add(Uint8List.sublistView(bytes, offset));
              break;
            }
            server.add(Uint8List.sublistView(bytes, offset, offset + frameLen));
            offset += frameLen;
            continue;
          }

          // Mensaje RTSP de texto
          final endOfHeader = _findDoubleCrlf(bytes, offset);
          if (endOfHeader == -1) {
            buffer.add(Uint8List.sublistView(bytes, offset));
            break;
          }

          final msgBytes = Uint8List.sublistView(bytes, offset, endOfHeader + 4);
          offset = endOfHeader + 4;

          var text = utf8.decode(msgBytes, allowMalformed: true);

          // Reescribir la URL local 127.0.0.1 a la URL original del DVR
          text = text.replaceAll('127.0.0.1:$_port', '${_targetUri.host}:${_targetUri.port}');

          // Asegurar transporte TCP interleaved en el comando SETUP
          if (text.startsWith('SETUP')) {
            text = text.replaceAll(
              RegExp(r'Transport:\s*RTP/AVP(/UDP)?', caseSensitive: false),
              'Transport: RTP/AVP/TCP;unicast;interleaved=0-1',
            );
          }

          // Añadir cabecera Authorization básica si el DVR tiene credenciales y no vino en la petición
          if (_targetUri.userInfo.isNotEmpty && !text.contains('Authorization:')) {
            final authBase64 = base64.encode(utf8.encode(_targetUri.userInfo));
            text = text.replaceFirst('\r\n\r\n', '\r\nAuthorization: Basic $authBase64\r\n\r\n');
          }

          server.add(utf8.encode(text));
        }
      },
      onError: (_) => _cleanup(client, server),
      onDone: () => _cleanup(client, server),
    );
  }

  void _pipeServerToClient(Socket server, Socket client, RtpStreamDecryptor decryptor) {
    final buffer = BytesBuilder(copy: false);

    server.listen(
      (data) {
        buffer.add(data);
        final bytes = buffer.toBytes();
        buffer.clear();

        var offset = 0;
        while (offset < bytes.length) {
          // Paquete interleaved ($)
          if (bytes[offset] == 0x24) { // '$'
            if (offset + 4 > bytes.length) {
              buffer.add(Uint8List.sublistView(bytes, offset));
              break;
            }
            final channel = bytes[offset + 1];
            final len = (bytes[offset + 2] << 8) | bytes[offset + 3];
            final frameLen = 4 + len;
            if (offset + frameLen > bytes.length) {
              buffer.add(Uint8List.sublistView(bytes, offset));
              break;
            }

            final rtpData = Uint8List.sublistView(bytes, offset + 4, offset + frameLen);
            offset += frameLen;

            // Canal 0 suele ser RTP Video en sesiones RTSP interleaved
            if (channel == 0) {
              final decryptedPackets = decryptor.processRtpPacket(rtpData);
              for (final p in decryptedPackets) {
                final frame = Uint8List(4 + p.length);
                frame[0] = 0x24; // '$'
                frame[1] = channel;
                frame[2] = (p.length >>> 8) & 0xFF;
                frame[3] = p.length & 0xFF;
                frame.setRange(4, 4 + p.length, p);
                client.add(frame);
              }
            } else {
              // Otros canales (RTCP o audio) pasan directos
              client.add(Uint8List.sublistView(bytes, offset - frameLen, offset));
            }
            continue;
          }

          // Respuesta RTSP de texto
          final endOfHeader = _findDoubleCrlf(bytes, offset);
          if (endOfHeader == -1) {
            buffer.add(Uint8List.sublistView(bytes, offset));
            break;
          }

          final msgBytes = Uint8List.sublistView(bytes, offset, endOfHeader + 4);
          offset = endOfHeader + 4;

          var text = utf8.decode(msgBytes, allowMalformed: true);
          // Reescribir host del DVR al host local para que el cliente continúe la sesión en el proxy
          text = text.replaceAll('${_targetUri.host}:${_targetUri.port}', '127.0.0.1:$_port');
          client.add(utf8.encode(text));
        }
      },
      onError: (_) => _cleanup(client, server),
      onDone: () => _cleanup(client, server),
    );
  }

  void _cleanup(Socket? s1, Socket? s2) {
    if (s1 != null) {
      _activeSockets.remove(s1);
      try { s1.destroy(); } catch (_) {}
    }
    if (s2 != null) {
      _activeSockets.remove(s2);
      try { s2.destroy(); } catch (_) {}
    }
  }

  static int _findDoubleCrlf(Uint8List bytes, int start) {
    for (var i = start; i < bytes.length - 3; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  /// Cierra el proxy y todos los sockets asociados.
  Future<void> dispose() async {
    _closed = true;
    for (final s in List<Socket>.from(_activeSockets)) {
      try { s.destroy(); } catch (_) {}
    }
    _activeSockets.clear();
    await _server?.close();
    _server = null;
  }
}
