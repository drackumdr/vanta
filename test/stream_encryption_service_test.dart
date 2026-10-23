import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vanta/models/device_model.dart';
import 'package:vanta/services/hikvision_service.dart';
import 'package:vanta/services/isapi_client.dart';

void main() {
  final testDevice = Device(
    id: 'dev-1',
    name: 'Test DVR',
    kind: DeviceKind.dvr,
    host: '192.168.1.141',
    username: 'admin',
    password: 'password123',
    createdAt: DateTime.now(),
  );

  group('HikvisionService.checkStreamEncryption', () {
    test('returns StreamEncryptionActive with code when streamEncrypteEnabled is true', () async {
      final mockHttp = MockClient((request) async {
        if (request.url.path == '/ISAPI/System/Network/EZVIZ') {
          final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<EZVIZ version="1.0" xmlns="http://www.std-cgi.com/ver20/XMLSchema">
  <enabled>true</enabled>
  <verificationCode>DVRDTK</verificationCode>
  <streamEncrypteEnabled>true</streamEncrypteEnabled>
</EZVIZ>''';
          return http.Response(xml, 200, headers: {'content-type': 'application/xml'});
        }
        return http.Response('Not Found', 404);
      });

      final client = IsapiClient(
        host: testDevice.host,
        port: testDevice.port,
        username: testDevice.username,
        password: testDevice.password,
        client: mockHttp,
      );
      final service = HikvisionService(testDevice, client: client);

      final status = await service.checkStreamEncryption();
      expect(status, isA<StreamEncryptionActive>());
      expect((status as StreamEncryptionActive).verificationCode, 'DVRDTK');
    });

    test('returns StreamEncryptionDisabled when streamEncrypteEnabled is false', () async {
      final mockHttp = MockClient((request) async {
        if (request.url.path == '/ISAPI/System/Network/EZVIZ') {
          final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<EZVIZ version="1.0" xmlns="http://www.std-cgi.com/ver20/XMLSchema">
  <enabled>true</enabled>
  <verificationCode>DVRDTK</verificationCode>
  <streamEncrypteEnabled>false</streamEncrypteEnabled>
</EZVIZ>''';
          return http.Response(xml, 200, headers: {'content-type': 'application/xml'});
        }
        return http.Response('Not Found', 404);
      });

      final client = IsapiClient(
        host: testDevice.host,
        port: testDevice.port,
        username: testDevice.username,
        password: testDevice.password,
        client: mockHttp,
      );
      final service = HikvisionService(testDevice, client: client);

      final status = await service.checkStreamEncryption();
      expect(status, isA<StreamEncryptionDisabled>());
    });

    test('returns StreamEncryptionUnsupported on 404 or missing EZVIZ element', () async {
      final mockHttp = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final client = IsapiClient(
        host: testDevice.host,
        port: testDevice.port,
        username: testDevice.username,
        password: testDevice.password,
        client: mockHttp,
      );
      final service = HikvisionService(testDevice, client: client);

      final status = await service.checkStreamEncryption();
      expect(status, isA<StreamEncryptionUnsupported>());
    });

    test('returns StreamEncryptionError on 401 Unauthorized', () async {
      final mockHttp = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final client = IsapiClient(
        host: testDevice.host,
        port: testDevice.port,
        username: testDevice.username,
        password: testDevice.password,
        client: mockHttp,
      );
      final service = HikvisionService(testDevice, client: client);

      final status = await service.checkStreamEncryption();
      expect(status, isA<StreamEncryptionError>());
      expect((status as StreamEncryptionError).message, contains('401'));
    });
  });

  group('HikvisionService.setStreamEncryption', () {
    test('properly sanitizes XML characters in verificationCode', () async {
      String? sentBody;
      final mockHttp = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/ISAPI/System/Network/EZVIZ') {
          return http.Response(
            '<EZVIZ><verificationCode>OLD</verificationCode></EZVIZ>',
            200,
            headers: {'content-type': 'application/xml'},
          );
        }
        if (request.method == 'PUT' && request.url.path == '/ISAPI/System/Network/EZVIZ') {
          sentBody = request.body;
          return http.Response('<ResponseStatus><statusCode>1</statusCode></ResponseStatus>', 200);
        }
        return http.Response('Not Found', 404);
      });

      final client = IsapiClient(
        host: testDevice.host,
        port: testDevice.port,
        username: testDevice.username,
        password: testDevice.password,
        client: mockHttp,
      );
      final service = HikvisionService(testDevice, client: client);

      final ok = await service.setStreamEncryption(false, verificationCode: 'KEY&<"\'TEST');
      expect(ok, isTrue);
      expect(sentBody, isNotNull);
      expect(sentBody, contains('<verificationCode>KEY&amp;&lt;&quot;&apos;TEST</verificationCode>'));
      expect(sentBody, contains('<streamEncrypteEnabled>false</streamEncrypteEnabled>'));
    });
  });
}
