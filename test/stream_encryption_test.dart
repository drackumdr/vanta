import 'package:flutter_test/flutter_test.dart';
import 'package:vanta/models/camera_model.dart';
import 'package:vanta/models/device_model.dart';
import 'package:vanta/state/app_state.dart';
import 'package:vanta/services/hikvision_service.dart';

void main() {
  group('Stream Encryption & Verification Code Models', () {
    test(
      'Device serialization preserves physical non-contiguous channel IDs',
      () {
        final device = Device(
          id: 'dev-1',
          name: 'DVR',
          kind: DeviceKind.dvr,
          host: '192.168.1.24',
          username: 'admin',
          password: 'password123',
          channelIds: const [1, 5, 8],
          createdAt: DateTime.now(),
        );

        final restored = Device.fromJson(
          device.toJson(),
          password: 'password123',
        );
        expect(restored.channelIds, [1, 5, 8]);
      },
    );

    test('AppState exposes non-contiguous physical channels', () {
      final app = AppState();
      app.devices = [
        Device(
          id: 'dev-1',
          name: 'DVR',
          kind: DeviceKind.dvr,
          host: '192.168.1.24',
          username: 'admin',
          password: 'password123',
          channelIds: const [1, 5],
          createdAt: DateTime.now(),
        ),
      ];

      expect(app.allCameras.map((camera) => camera.channel), [1, 5]);
      app.dispose();
    });

    test(
      'Device serialization preserves streamEncryption and excludes sensitive credentials',
      () {
        final device = Device(
          id: 'dev-1',
          name: 'NVR Entrada',
          kind: DeviceKind.dvr,
          host: '192.168.1.141',
          username: 'admin',
          password: 'password123',
          createdAt: DateTime.now(),
          streamEncryption: true,
          verificationCode: 'DVRDTK',
        );

        final json = device.toJson();
        expect(json['streamEncryption'], isTrue);
        // Las credenciales sensibles no se guardan en el JSON plano (se usan en SecureStore)
        expect(json.containsKey('password'), isFalse);
        expect(json.containsKey('verificationCode'), isFalse);

        final restored = Device.fromJson(
          json,
          password: 'password123',
          verificationCode: 'DVRDTK',
        );
        expect(restored.streamEncryption, isTrue);
        expect(restored.verificationCode, 'DVRDTK');
        expect(restored.password, 'password123');
      },
    );

    test(
      'Device.fromJson falls back to json verificationCode for legacy data',
      () {
        final legacyJson = {
          'id': 'dev-legacy',
          'name': 'Legacy DVR',
          'kind': 'dvr',
          'host': '192.168.1.150',
          'username': 'admin',
          'streamEncryption': true,
          'verificationCode': 'LEGACYCODE',
          'createdAt': DateTime.now().toIso8601String(),
        };
        final dev = Device.fromJson(legacyJson, password: 'pass');
        expect(dev.streamEncryption, isTrue);
        expect(dev.verificationCode, 'LEGACYCODE');
        expect(dev.password, 'pass');
      },
    );

    test('Camera inherits verificationCode from Device when encrypted', () {
      final device = Device(
        id: 'dev-1',
        name: 'DVR',
        kind: DeviceKind.dvr,
        host: '192.168.1.141',
        username: 'admin',
        password: 'password123',
        createdAt: DateTime.now(),
        streamEncryption: true,
        verificationCode: 'DVRDTK',
      );

      final cam = Camera.forDevice(device, 1);
      expect(cam.verificationCode, 'DVRDTK');
      expect(cam.effectiveVerificationCode(device), 'DVRDTK');
    });

    test('Camera verificationCode override takes precedence', () {
      final device = Device(
        id: 'dev-1',
        name: 'DVR',
        kind: DeviceKind.dvr,
        host: '192.168.1.141',
        username: 'admin',
        password: 'password123',
        createdAt: DateTime.now(),
        streamEncryption: true,
        verificationCode: 'DVRDTK',
      );

      final cam = Camera.forDevice(device, 2, verificationCode: 'CUSTOMKEY');
      expect(cam.verificationCode, 'CUSTOMKEY');
      expect(cam.effectiveVerificationCode(device), 'CUSTOMKEY');
    });

    test('StreamEncryptionStatus type hierarchy', () {
      const active = StreamEncryptionActive(verificationCode: 'DVRDTK');
      const disabled = StreamEncryptionDisabled();
      const unsupported = StreamEncryptionUnsupported();
      const error = StreamEncryptionError('Timeout 401');

      expect(active.verificationCode, 'DVRDTK');
      expect(active, isA<StreamEncryptionStatus>());
      expect(disabled, isA<StreamEncryptionStatus>());
      expect(unsupported, isA<StreamEncryptionStatus>());
      expect(error.message, 'Timeout 401');
      expect(error, isA<StreamEncryptionStatus>());
    });
  });
}
