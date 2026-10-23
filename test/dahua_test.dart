import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vanta/models/device_model.dart';
import 'package:vanta/services/dahua_service.dart';
import 'package:vanta/services/isapi_client.dart';
import 'package:vanta/services/rtsp_url_builder.dart';

Device _dahua() => Device(
      id: 'd1',
      name: 'NVR Dahua',
      kind: DeviceKind.nvr,
      brand: DeviceBrand.dahua,
      host: '192.168.1.108',
      rtspPort: 554,
      username: 'admin',
      password: 'p@ss/w',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('RtspUrlBuilder (Dahua)', () {
    final d = _dahua();

    test('live usa realmonitor con subtype según calidad', () {
      expect(
        RtspUrlBuilder.live(d, 2, main: true),
        'rtsp://admin:p%40ss%2Fw@192.168.1.108:554'
        '/cam/realmonitor?channel=2&subtype=0',
      );
      expect(
        RtspUrlBuilder.live(d, 2, main: false),
        'rtsp://admin:p%40ss%2Fw@192.168.1.108:554'
        '/cam/realmonitor?channel=2&subtype=1',
      );
    });

    test('playback usa formato YYYY_MM_DD_HH_MM_SS y subtype=0', () {
      expect(
        RtspUrlBuilder.playback(
          d,
          1,
          DateTime(2026, 10, 22, 9, 0, 0),
          DateTime(2026, 10, 22, 9, 10, 5),
        ),
        'rtsp://admin:p%40ss%2Fw@192.168.1.108:554'
        '/cam/playback?channel=1&subtype=0'
        '&starttime=2026_10_22_09_00_00&endtime=2026_10_22_09_10_05',
      );
    });
  });

  test('Device serializa y restaura la marca', () {
    final json = _dahua().toJson();
    expect(json['brand'], 'dahua');
    expect(Device.fromJson(json).brand, DeviceBrand.dahua);
  });

  group('DahuaService.searchRecordings', () {
    test('crea sesión, pagina findNextFile y cierra', () async {
      final calls = <String>[];
      var pages = 0;
      final mock = MockClient((request) async {
        final q = request.url.query;
        calls.add(q);
        if (q.contains('factory.create')) {
          return http.Response('result=42', 200);
        }
        if (q.contains('action=findFile')) {
          return http.Response('OK', 200);
        }
        if (q.contains('action=findNextFile')) {
          if (pages++ > 0) return http.Response('Error=NoMoreFiles', 200);
          return http.Response(
            'items[0].StartTime=2026-10-22 09:00:00\n'
            'items[0].EndTime=2026-10-22 09:05:00\n'
            'items[1].StartTime=2026-10-22 10:00:00\n'
            'items[1].EndTime=2026-10-22 10:30:00\n',
            200,
          );
        }
        if (q.contains('action=close') || q.contains('action=destroy')) {
          return http.Response('OK', 200);
        }
        return http.Response('Error', 400);
      });

      final client = IsapiClient(
        host: '192.168.1.108',
        port: 80,
        username: 'admin',
        password: 'x',
        client: mock,
      );
      final service = DahuaService(_dahua(), client: client);

      final segs = await service.searchRecordings(
        channel: 1,
        start: DateTime(2026, 10, 22),
        end: DateTime(2026, 10, 23),
      );

      expect(segs.length, 2);
      expect(segs.first.startLocal, DateTime(2026, 10, 22, 9, 0, 0));
      expect(segs.first.endLocal, DateTime(2026, 10, 22, 9, 5, 0));
      expect(calls.any((c) => c.contains('action=close')), isTrue);
      expect(calls.any((c) => c.contains('action=destroy')), isTrue);
    });

    test('parsea fechas con comillas y soporta mp4', () async {
      var nextCalls = 0;
      final mock = MockClient((request) async {
        final q = request.url.query;
        if (q.contains('factory.create')) return http.Response('result=7', 200);
        if (q.contains('action=findFile')) return http.Response('OK', 200);
        if (q.contains('action=findNextFile')) {
          if (nextCalls++ > 0) return http.Response('OK', 200);
          return http.Response(
            'items[0].StartTime="2026-10-22 14:00:00"\n'
            'items[0].EndTime="2026-10-22 14:30:00"\n',
            200,
          );
        }
        return http.Response('OK', 200);
      });

      final client = IsapiClient(
        host: '192.168.1.108',
        port: 80,
        username: 'admin',
        password: 'x',
        client: mock,
      );
      final service = DahuaService(_dahua(), client: client);
      final segs = await service.searchRecordings(
        channel: 1,
        start: DateTime(2026, 10, 22),
        end: DateTime(2026, 10, 23),
      );

      expect(segs.length, 1);
      expect(segs.first.startLocal, DateTime(2026, 10, 22, 14, 0, 0));
      expect(segs.first.endLocal, DateTime(2026, 10, 22, 14, 30, 0));
    });

    test('fetchChannels descubre nombres reales vía ChannelTitle', () async {
      final mock = MockClient((request) async {
        if (request.url.query.contains('name=ChannelTitle')) {
          return http.Response(
            'table.ChannelTitle[0].Name=Entrada\n'
            'table.ChannelTitle[1].Name=Patio\n',
            200,
          );
        }
        return http.Response('Error', 400);
      });

      final client = IsapiClient(
        host: '192.168.1.108',
        port: 80,
        username: 'admin',
        password: 'x',
        client: mock,
      );
      final service = DahuaService(_dahua(), client: client);
      final chs = await service.fetchChannels();

      expect(chs.length, 2);
      expect(chs[0].name, 'Entrada');
      expect(chs[0].id, 1);
      expect(chs[1].name, 'Patio');
      expect(chs[1].id, 2);
    });

    test('IsapiClient resuelve challenge Digest Dahua con qop múltiple o sin comillas', () async {
      var step = 0;
      String? authReceived;
      final mock = MockClient((request) async {
        if (step++ == 0) {
          return http.Response(
            'Unauthorized',
            401,
            headers: {
              'www-authenticate':
                  'Digest realm="Login to DAHUA", qop="auth,auth-int", nonce="abc12345", opaque="opq999"',
            },
          );
        }
        authReceived = request.headers['Authorization'];
        return http.Response('OK', 200);
      });

      final client = IsapiClient(
        host: '192.168.1.108',
        port: 80,
        username: 'admin',
        password: 'password123',
        client: mock,
      );

      final r = await client.get('/cgi-bin/magicBox.cgi?action=getDeviceType');
      expect(r.statusCode, 200);
      expect(authReceived, isNotNull);
      expect(authReceived, contains('qop=auth'));
      expect(authReceived, contains('realm="Login to DAHUA"'));
      expect(authReceived, contains('nonce="abc12345"'));
      expect(authReceived, isNot(contains('auth,auth-int')));
    });
  });
}
