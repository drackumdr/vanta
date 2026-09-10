import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Categorías de error amigables para el usuario final.
enum ApiErrorKind { offline, timeout, auth, forbidden, notFound, server, other }

class IsapiException implements Exception {
  final ApiErrorKind kind;
  final String message;
  IsapiException(this.kind, this.message);

  @override
  String toString() => 'IsapiException($kind): $message';
}

class _DigestChallenge {
  final String realm;
  final String nonce;
  final String qop;
  final String? opaque;
  _DigestChallenge({required this.realm, required this.nonce, required this.qop, this.opaque});
}

/// Cliente HTTP ISAPI con autenticación Digest (RFC-2617 qop=auth).
/// Port del driver probado de "control de acceso" (BioAccess PRO).
class IsapiClient {
  IsapiClient({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.https = false,
    this.timeout = const Duration(seconds: 8),
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final bool https;
  final Duration timeout;

  final http.Client _client = http.Client();
  _DigestChallenge? _challenge;
  String _cnonce = _randomCnonce();
  int _nc = 0;

  String get baseUrl => '${https ? 'https' : 'http'}://$host:$port';

  Future<http.Response> get(String path) => _send('GET', path);

  Future<http.Response> getBytes(String path) =>
      _send('GET', path, acceptBinary: true);

  Future<http.Response> post(
    String path, {
    String? body,
    String contentType = 'application/xml; charset=UTF-8',
  }) =>
      _send('POST', path, body: body, contentType: contentType);

  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
    String? contentType,
    bool acceptBinary = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    _challenge ??= null;

    var response = await _requestRaw(
      uri,
      method,
      body: body,
      contentType: contentType,
      authHeader: _challenge == null ? null : _buildAuth(method, uri),
      acceptBinary: acceptBinary,
    );

    if (response.statusCode == 401) {
      final challenge = _parseChallenge(response.headers['www-authenticate']);
      if (challenge == null) {
        throw IsapiException(ApiErrorKind.auth, 'Autenticación fallida (401)');
      }
      _challenge = challenge;
      _nc = 0;
      _cnonce = _randomCnonce();
      response = await _requestRaw(
        uri,
        method,
        body: body,
        contentType: contentType,
        authHeader: _buildAuth(method, uri),
        acceptBinary: acceptBinary,
      );
      if (response.statusCode == 401) {
        throw IsapiException(ApiErrorKind.auth, 'Autenticación fallida (401)');
      }
    }
    _handleStatus(response.statusCode);
    return response;
  }

  void _handleStatus(int status) {
    switch (status) {
      case 200:
      case 202:
        return;
      case 401:
        throw IsapiException(ApiErrorKind.auth, 'Autenticación fallida');
      case 403:
        throw IsapiException(ApiErrorKind.forbidden, 'Operación no permitida por el dispositivo');
      case 404:
      case 405:
        throw IsapiException(ApiErrorKind.notFound, 'Función no soportada por el dispositivo');
      case 500:
      case 502:
      case 503:
        throw IsapiException(ApiErrorKind.server, 'El dispositivo reportó un error');
      case 408:
        throw IsapiException(ApiErrorKind.timeout, 'Tiempo de espera agotado');
      default:
        throw IsapiException(ApiErrorKind.other, 'Error HTTP $status');
    }
  }

  Future<http.Response> _requestRaw(
    Uri uri,
    String method, {
    String? body,
    String? contentType,
    String? authHeader,
    bool acceptBinary = false,
  }) async {
    try {
      final request = http.Request(method, uri);
      request.headers['Content-Type'] = contentType ?? 'application/json';
      request.headers['Accept'] = acceptBinary ? '*/*' : 'text/xml';
      if (authHeader != null) {
        request.headers['Authorization'] = authHeader;
      }
      if (body != null && body.isNotEmpty) {
        request.body = body;
      }
      final streamed = await _client.send(request).timeout(timeout);
      return http.Response.fromStream(streamed);
    } on IsapiException {
      rethrow;
    } on TimeoutException {
      throw IsapiException(ApiErrorKind.timeout, 'Tiempo de espera agotado');
    } catch (e) {
      throw IsapiException(ApiErrorKind.offline, 'No se pudo conectar al dispositivo');
    }
  }

  _DigestChallenge? _parseChallenge(String? header) {
    if (header == null || !header.startsWith('Digest')) return null;
    final params = <String, String>{};
    final regex = RegExp(r'(\w+)="([^"]*)"');
    for (final m in regex.allMatches(header)) {
      params[m.group(1)!.toLowerCase()] = m.group(2)!;
    }
    return _DigestChallenge(
      realm: params['realm'] ?? '',
      nonce: params['nonce'] ?? '',
      qop: params['qop'] ?? 'auth',
      opaque: params['opaque'],
    );
  }

  String? _buildAuth(String method, Uri uri) {
    final c = _challenge;
    if (c == null || c.nonce.isEmpty) return null;
    _nc++;
    final ncStr = _nc.toRadixString(16).padLeft(8, '0');
    final digestUri = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final ha1 = _md5('$username:${c.realm}:$password');
    final ha2 = _md5('$method:$digestUri');
    final response = _md5('$ha1:${c.nonce}:$ncStr:$_cnonce:${c.qop}:$ha2');
    final sb = StringBuffer()
      ..write('Digest username="$username", realm="${c.realm}", nonce="${c.nonce}", ')
      ..write('uri="$digestUri", qop=${c.qop}, nc=$ncStr, cnonce="$_cnonce", response="$response"');
    if (c.opaque != null && c.opaque!.isNotEmpty) {
      sb.write(', opaque="${c.opaque}"');
    }
    return sb.toString();
  }

  static String _md5(String input) =>
      md5.convert(utf8.encode(input)).toString();

  static String _randomCnonce() {
    final rng = Random.secure();
    return List.generate(8, (_) => rng.nextInt(255).toRadixString(16).padLeft(2, '0')).join();
  }

  void dispose() => _client.close();
}