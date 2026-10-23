import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../models/camera_model.dart';
import '../models/device_model.dart';
import '../models/view_model.dart';
import '../services/rtsp_url_builder.dart';
import '../services/secure_store.dart';
import '../services/settings_store.dart';
import '../services/stream_manager.dart';

/// Estado central de la aplicación (fuente de verdad de la UI).
class AppState extends ChangeNotifier {
  AppState() {
    streams.addListener(_onStreamsChanged);
  }

  void _onStreamsChanged() {
    notifyListeners();
  }

  static const _uuid = Uuid();

  final SecureStore _secure = SecureStore.instance;
  final SettingsStore _settings = SettingsStore.instance;
  final StreamManager streams = StreamManager();

  bool _loading = false;
  bool _loaded = false;
  bool get loading => _loading;
  bool get loaded => _loaded;

  List<Device> devices = [];
  List<SurveillanceView> views = [];

  // Layout activo (efímero o vinculado a una vista guardada).
  GridSize gridSize = GridSize.four;
  late List<String?> cells = List<String?>.filled(gridSize.count, null);
  String? activeViewId;

  /// Calidad usada por las cámaras del grid. La pantalla completa siempre usa
  /// el stream principal.
  bool mainStreamInGrid = false;

  /// Cámara en pantalla completa (último sync la usa con stream principal).
  String? focusCameraId;

  StreamManager get streamManager => streams;

  // --------------------------------------------------------------- ciclo
  Future<void> load() async {
    if (_loaded || _loading) return;
    _loading = true;
    notifyListeners();
    await _settings.init();
    await _hydrateDevices();
    _hydrateViews();
    _restoreLastLayout();

    final hasValidCamera = cells.any((c) => c != null && cameraById(c) != null);
    if (!hasValidCamera && allCameras.isNotEmpty) {
      showAllCameras();
    } else {
      syncStreams();
    }

    _loading = false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _hydrateDevices() async {
    final metas = _settings.devices;
    final list = <Device>[];
    for (final meta in metas) {
      final id = meta['id'] as String;
      final password = (await _secure.readPassword(id)) ?? '';
      final verificationCode = (await _secure.readVerificationCode(id)) ?? '';
      list.add(
        Device.fromJson(
          meta,
          password: password,
          verificationCode: verificationCode,
        ),
      );
    }
    devices = list;
  }

  void _hydrateViews() {
    views = _settings.views
        .map(SurveillanceView.fromJson)
        .where((v) => v.id.isNotEmpty)
        .toList();
  }

  void _restoreLastLayout() {
    final view = views.where((v) => v.id == _settings.activeViewId).firstOrNull;
    final layout = _settings.lastLayout;
    if (view != null) {
      _applyView(view, persist: false);
    } else if (layout != null) {
      gridSize = layout.gridSize;
      cells = List<String?>.from(layout.cells);
      while (cells.length < gridSize.count) {
        cells.add(null);
      }
      activeViewId = null;
    }
  }

  // ------------------------------------------------------- lookup helpers
  Device? deviceById(String id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  Camera? cameraById(String? cameraId) {
    if (cameraId == null) return null;
    final parts = cameraId.split(':');
    if (parts.length != 2) return null;
    final device = deviceById(parts[0]);
    if (device == null) return null;
    return Camera.forDevice(device, int.tryParse(parts[1]) ?? 1);
  }

  List<Camera> get allCameras => [
    for (final d in devices)
      for (final ch
          in d.channelIds.isNotEmpty
              ? d.channelIds
              : List<int>.generate(
                  d.channelCount == 0 ? 1 : d.channelCount,
                  (i) => i + 1,
                ))
        Camera.forDevice(d, ch),
  ];

  // --------------------------------------------------------- dispositivos
  Future<void> saveDevice(Device device) async {
    final idx = devices.indexWhere((d) => d.id == device.id);
    if (idx >= 0) {
      devices[idx] = device;
    } else {
      devices.add(device);
    }
    await _secure.writePassword(device.id, device.password);
    await _secure.writeVerificationCode(device.id, device.verificationCode);
    await _persistDevices();

    final hasValidCamera = cells.any((c) => c != null && cameraById(c) != null);
    if (!hasValidCamera && allCameras.isNotEmpty) {
      showAllCameras();
    } else {
      syncStreams();
    }
    notifyListeners();
  }

  Future<void> removeDevice(String id) async {
    devices.removeWhere((d) => d.id == id);
    await _secure.deletePassword(id);
    await _secure.deleteVerificationCode(id);
    await _persistDevices();
    final cameraIds = allCameras.map((c) => c.id).toSet();
    cells = cells
        .map((c) => (c != null && cameraIds.contains(c)) ? null : c)
        .toList();
    if (focusCameraId != null &&
        cameraIds.contains(focusCameraId!.split(':').first)) {
      focusCameraId = null;
    }
    await _persistLayout();
    notifyListeners();
  }

  Future<void> _persistDevices() async {
    await _settings.saveDevices(devices.map((d) => d.toJson()).toList());
  }

  // -------------------------------------------------------------- layout
  void setGridSize(GridSize size) {
    if (size == gridSize) return;
    final previous = cells;
    gridSize = size;
    cells = List<String?>.generate(
      size.count,
      (i) => i < previous.length ? previous[i] : null,
    );
    activeViewId = null;
    _persistLayout();
    syncStreams();
    notifyListeners();
  }

  void setMainStreamInGrid(bool value) {
    if (mainStreamInGrid == value) return;
    mainStreamInGrid = value;
    syncStreams();
    notifyListeners();
  }

  void assignCamera(int position, String? cameraId) {
    if (position < 0 || position >= cells.length) return;
    cells[position] = cameraId;
    activeViewId = null;
    _persistLayout();
    syncStreams();
    notifyListeners();
  }

  void clearSlot(int position) => assignCamera(position, null);

  void showAllCameras() {
    final cameras = allCameras;
    final size = switch (cameras.length) {
      0 || 1 => GridSize.one,
      2 || 3 || 4 => GridSize.four,
      5 || 6 => GridSize.six,
      7 || 8 || 9 => GridSize.nine,
      _ => GridSize.sixteen,
    };
    gridSize = size;
    cells = List<String?>.generate(
      size.count,
      (i) => i < cameras.length ? cameras[i].id : null,
    );
    activeViewId = null;
    _persistLayout();
    syncStreams();
    notifyListeners();
  }

  void setFocusCamera(String? cameraId) {
    if (focusCameraId == cameraId) return;
    focusCameraId = cameraId;
    syncStreams();
    // Notificación diferida a post-frame: este método se invoca también
    // desde dispose()/handlers de teclado durante el frame (árbol bloqueado),
    // y notificar ahí lanza "markNeedsBuild() called when widget tree was locked".
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }
  

  // --------------------------------------------------------------- vistas
  Future<void> saveAsView(String name) async {
    final view = SurveillanceView(
      id: _uuid.v4(),
      name: name,
      gridSize: gridSize,
      cells: List<String?>.from(cells),
      updatedAt: DateTime.now(),
    );
    views.insert(0, view);
    await _settings.saveViews(views.map((v) => v.toJson()).toList());
    applyView(view);
  }

  void applyView(SurveillanceView view) {
    _applyView(view, persist: true);
    syncStreams();
    notifyListeners();
  }

  void _applyView(SurveillanceView view, {required bool persist}) {
    gridSize = view.gridSize;
    cells = List<String?>.from(view.cells);
    while (cells.length < gridSize.count) {
      cells.add(null);
    }
    activeViewId = view.id;
    if (persist) _persistLayout();
  }

  Future<void> deleteView(String id) async {
    views.removeWhere((v) => v.id == id);
    await _settings.saveViews(views.map((v) => v.toJson()).toList());
    if (activeViewId == id) {
      activeViewId = null;
      await _settings.saveActiveViewId(null);
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- streams
  /// Calcula el conjunto deseado de streams y sincroniza (grid + foco).
  void syncStreams() {
    final desired = <String, String>{};
    final vCodes = <String, String>{};

    void add(Camera camera, {required bool main}) {
      final device = deviceById(camera.deviceId);
      if (device == null) return;
      desired[camera.id] = RtspUrlBuilder.live(
        device,
        camera.channel,
        main: main,
      );
      if (device.streamEncryption) {
        final code = camera.effectiveVerificationCode(device);
        if (code.isNotEmpty) {
          vCodes[camera.id] = code;
        }
      }
    }

    final focus = cameraById(focusCameraId);
    if (focus != null) add(focus, main: true);

    final useMainAny = gridSize.useMainStream || mainStreamInGrid;
    for (final cameraId in cells) {
      final camera = cameraById(cameraId);
      if (camera != null && cameraId != focusCameraId) {
        add(camera, main: useMainAny);
      }
    }

    streams.sync(desired, verificationCodes: vCodes).then((_) {
      notifyListeners();
    }).catchError((
      Object e,
      StackTrace st,
    ) {
      debugPrint('syncStreams error: $e');
    });
  }

  Future<void> _persistLayout() async {
    await _settings.saveLastLayout(
      LastLayout(gridSize: gridSize, cells: List<String?>.from(cells)),
    );
    await _settings.saveActiveViewId(activeViewId);
  }

  @override
  void dispose() {
    streams.removeListener(_onStreamsChanged);
    streams.disposeAll();
    super.dispose();
  }
}
