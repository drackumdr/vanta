import '../models/device_model.dart';
import '../models/recording_models.dart';
import 'dahua_service.dart';
import 'hikvision_service.dart';

/// Contrato común para la búsqueda de grabaciones (Hikvision y Dahua).
abstract class RecordingService {
  Future<Duration> fetchDeviceUtcOffset();
  Future<List<String>> fetchSearchTargetTypes();
  Future<List<RecordingSegment>> searchRecordings({
    required int channel,
    required DateTime start,
    required DateTime end,
    int maxResults,
  });
  Future<List<RecordingSegment>> searchByTargetType({
    required int channel,
    required List<String> targetTypes,
    required DateTime start,
    required DateTime end,
    int maxResults,
  });
}

/// Devuelve el servicio de grabaciones según la marca del dispositivo.
RecordingService recordingServiceFor(Device device) =>
    device.brand == DeviceBrand.dahua
        ? DahuaService(device)
        : HikvisionService(device);
