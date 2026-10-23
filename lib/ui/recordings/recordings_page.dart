import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/camera_model.dart';
import '../../models/device_model.dart';
import '../../models/recording_models.dart';
import '../../services/recording_service.dart';
import '../../services/rtsp_url_builder.dart';
import '../../state/app_state.dart';
import '../../video/encryption/rtsp_decryption_proxy.dart';
import '../../video/video_sink.dart';
import '../../widgets/camera_tile.dart';
import '../tv/tv_focusable.dart';
import 'timeline_widget.dart';

String monthKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Estación de trabajo profesional de reproducción de grabaciones (VMS).
/// Soporta hasta 4 cámaras simultáneas, selector de cámaras y calendario a la izquierda,
/// y línea de tiempo interactiva arrastrable debajo del video.
class RecordingsPage extends StatefulWidget {
  const RecordingsPage({
    super.key,
    this.deviceId,
    this.channel,
    this.initialCameraId,
  });

  final String? deviceId;
  final int? channel;
  final String? initialCameraId;

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  static const List<Color> _trackColors = [
    Color(0xFF2F9BFF), // Pista 1: Azul
    Color(0xFF4CAF50), // Pista 2: Verde
    Color(0xFFFFB300), // Pista 3: Ámbar / Naranja
    Color(0xFFAB47BC), // Pista 4: Violeta
  ];

  final Map<String, RecordingService> _services = {};
  final List<Camera> _selectedCameras = [];
  final Map<String, List<RecordingSegment>> _cameraSegments = {};
  final Map<String, VideoSink> _sessions = {};
  final Map<String, RtspDecryptionProxy> _proxies = {};
  final Map<String, String?> _sessionErrors = {};

  String? _focusedCameraId;
  Duration _offset = Duration.zero;
  bool _ready = false;

  late DateTime _today;
  late DateTime _selectedDay;
  DateTime _viewportMonth = DateTime.now();

  final Map<String, Map<int, bool>> _markers = {};
  final Set<String> _loadingMonths = {};
  bool _loadingSegments = false;

  // Estado de reproducción y playhead
  double _currentSeconds = 0.0;
  bool _isPlaying = false;
  bool _muted = true;
  Timer? _playheadTimer;

  List<String> _targetTypes = [];
  String? _selectedTargetType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  RecordingService _serviceFor(Device device) =>
      _services.putIfAbsent(device.id, () => recordingServiceFor(device));

  Future<void> _init() async {
    final app = Provider.of<AppState>(context, listen: false);
    final all = app.allCameras;
    if (all.isEmpty) {
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _today = DateTime(now.year, now.month, now.day);
          _selectedDay = _today;
          _viewportMonth = _today;
          _ready = true;
        });
      }
      return;
    }

    // Identificar cámara inicial a preseleccionar
    Camera? initial;
    if (widget.deviceId != null && widget.channel != null) {
      initial = all
          .where(
            (c) => c.deviceId == widget.deviceId && c.channel == widget.channel,
          )
          .firstOrNull;
    } else if (widget.initialCameraId != null) {
      initial = all.where((c) => c.id == widget.initialCameraId).firstOrNull;
    }
    initial ??= all.first;

    _selectedCameras.add(initial);

    final device = app.deviceById(initial.deviceId);
    if (device != null) {
      final service = _serviceFor(device);
      try {
        _offset = await service.fetchDeviceUtcOffset();
      } catch (_) {
        _offset = Duration.zero;
      }
      final targetTypes = await service.fetchSearchTargetTypes();
      if (mounted) {
        setState(() => _targetTypes = targetTypes);
      }
    }

    final deviceNow = DateTime.now().toUtc().add(_offset);
    final dateOnly = DateTime(deviceNow.year, deviceNow.month, deviceNow.day);
    _today = dateOnly;
    _selectedDay = dateOnly;
    _viewportMonth = dateOnly;

    if (mounted) {
      setState(() => _ready = true);
      _loadMonth(dateOnly);
      _loadSegmentsForDay(_selectedDay);
    }
  }

  // ------------------------------------------------------------- Consultas
  String _markerKey(DateTime month) {
    final cameras = _selectedCameras.map((c) => c.id).join(',');
    return '$cameras|${monthKeyOf(month)}';
  }

  Future<List<RecordingSegment>> _search(
    RecordingService service,
    Camera camera,
    DateTime start,
    DateTime end, {
    int maxResults = 300,
  }) {
    final target = _selectedTargetType;
    if (target == null) {
      return service.searchRecordings(
        channel: camera.channel,
        start: start,
        end: end,
        maxResults: maxResults,
      );
    }
    return service.searchByTargetType(
      channel: camera.channel,
      targetTypes: [target],
      start: start,
      end: end,
      maxResults: maxResults,
    );
  }

  Future<void> _loadMonth(DateTime monthDay) async {
    final key = _markerKey(monthDay);
    if (_markers.containsKey(key) || _loadingMonths.contains(key)) return;
    if (_selectedCameras.isEmpty) return;

    final app = context.read<AppState>();
    final cameras = List<Camera>.from(_selectedCameras);

    _loadingMonths.add(key);
    setState(() {});

    final year = monthDay.year, month = monthDay.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final map = <int, bool>{};

    Future<void> probe(int d) async {
      final day = DateTime(year, month, d);
      if (day.isAfter(_today)) {
        map[d] = false;
        return;
      }
      final end = DateTime(year, month, d, 23, 59, 59);
      map[d] = false;
      for (final camera in cameras) {
        final device = app.deviceById(camera.deviceId);
        if (device == null) continue;
        try {
          final list = await _search(
            _serviceFor(device),
            camera,
            day,
            end,
            maxResults: 1,
          );
          if (list.isNotEmpty) {
            map[d] = true;
            break;
          }
        } catch (_) {
          // Probar la siguiente cámara seleccionada.
        }
      }
    }

    final batches = <List<int>>[];
    for (var d = 1; d <= daysInMonth; d += 5) {
      final size = (d + 4) <= daysInMonth ? 5 : (daysInMonth - d + 1);
      batches.add(List.generate(size, (i) => d + i));
    }
    for (final batch in batches) {
      await Future.wait(batch.map(probe));
    }

    if (mounted) {
      _markers[key] = map;
      _loadingMonths.remove(key);
      setState(() {});
    }
  }

  Future<void> _loadSegmentsForDay(DateTime day) async {
    final app = context.read<AppState>();
    setState(() {
      _loadingSegments = true;
      _selectedDay = day;
    });

    for (final cam in _selectedCameras) {
      final device = app.deviceById(cam.deviceId);
      if (device == null) continue;
      final service = _serviceFor(device);
      final start = DateTime(day.year, day.month, day.day);
      final end = DateTime(day.year, day.month, day.day, 23, 59, 59);

      try {
        final list = await _search(
          service,
          cam,
          start,
          end,
          maxResults: 300,
        );
        if (mounted) {
          _cameraSegments[cam.id] = list;
        }
      } catch (_) {
        if (mounted) {
          _cameraSegments[cam.id] = [];
        }
      }
    }

    if (mounted) {
      setState(() => _loadingSegments = false);
      _autoPositionPlayhead();
    }
  }

  void _autoPositionPlayhead() {
    final dayStart = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    for (final cam in _selectedCameras) {
      final segs = _cameraSegments[cam.id];
      if (segs != null && segs.isNotEmpty) {
        final first = segs.first;
        final start = first.startLocal;
        final sec = start.isBefore(dayStart)
            ? 0.0
            : start.difference(dayStart).inSeconds.toDouble().clamp(0.0, 86400.0);
        setState(() => _currentSeconds = sec);
        _seekTo(sec, autoPlay: false);
        return;
      }
    }
  }

  // ------------------------------------------------------------- Selección de cámaras
  void _toggleCamera(Camera cam) {
    final exists = _selectedCameras.any((c) => c.id == cam.id);
    if (exists) {
      if (_selectedCameras.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debe haber al menos una cámara seleccionada.'),
          ),
        );
        return;
      }
      final session = _sessions.remove(cam.id);
      session?.dispose();
      _cameraSegments.remove(cam.id);
      _sessionErrors.remove(cam.id);
      if (_focusedCameraId == cam.id) _focusedCameraId = null;
      setState(() => _selectedCameras.removeWhere((c) => c.id == cam.id));
      _loadMonth(_viewportMonth);
    } else {
      if (_selectedCameras.length >= 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Máximo 4 cámaras en reproducción simultánea.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      setState(() => _selectedCameras.add(cam));
      _loadSegmentsForSingleCamera(cam);
      _loadMonth(_viewportMonth);
    }
  }

  Future<void> _loadSegmentsForSingleCamera(Camera cam) async {
    final device = context.read<AppState>().deviceById(cam.deviceId);
    if (device == null) return;
    final service = _serviceFor(device);
    final start = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final end = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      23,
      59,
      59,
    );

    try {
      final list = await _search(
      service,
      cam,
      start,
      end,
      maxResults: 300,
    );
    if (mounted) {
      setState(() => _cameraSegments[cam.id] = list);
        if (_isPlaying) {
          _seekCamera(cam, _currentSeconds, autoPlay: true);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cameraSegments[cam.id] = []);
      }
    }
  }

  // ------------------------------------------------------------- Playback / Seeking
  Future<void> _seekTo(double seconds, {bool autoPlay = true}) async {
    setState(() => _currentSeconds = seconds);
    for (final cam in _selectedCameras) {
      await _seekCamera(cam, seconds, autoPlay: autoPlay);
    }

    if (mounted) {
      setState(() => _isPlaying = autoPlay);
      if (autoPlay) {
        _startPlayheadTimer();
      } else {
        _playheadTimer?.cancel();
      }
    }
  }

  Future<void> _seekCamera(
    Camera cam,
    double seconds, {
    required bool autoPlay,
  }) async {
    final device = context.read<AppState>().deviceById(cam.deviceId);
    if (device == null) return;

    final segs = _cameraSegments[cam.id] ?? [];
    final targetTime = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    ).add(Duration(seconds: seconds.toInt()));

    RecordingSegment? match;
    for (final s in segs) {
      if ((targetTime.isAfter(s.startLocal) ||
              targetTime.isAtSameMomentAs(s.startLocal)) &&
          targetTime.isBefore(s.endLocal)) {
        match = s;
        break;
      }
    }

    if (match != null) {
      var url =
          RtspUrlBuilder.fromPlaybackUri(
            device,
            match.playbackUri,
            startLocal: targetTime,
            endLocal: match.endLocal,
          ) ??
          RtspUrlBuilder.playback(device, cam.channel, targetTime, match.endLocal);

      final vCode = device.streamEncryption ? cam.effectiveVerificationCode(device) : '';
      if (vCode.isNotEmpty) {
        var proxy = _proxies[cam.id];
        if (proxy == null || proxy.targetUrl != url) {
          await proxy?.dispose();
          proxy = RtspDecryptionProxy(targetUrl: url, verificationCode: vCode);
          await proxy.start();
          _proxies[cam.id] = proxy;
        }
        url = proxy.loopbackUrl;
      } else {
        final oldProxy = _proxies.remove(cam.id);
        await oldProxy?.dispose();
      }

      try {
        var session = _sessions[cam.id];
        if (session == null) {
          session = await createVideoSink(url);
          if (!mounted) {
            await session.dispose();
            return;
          }
          await session.setMuted(_muted);
          _sessions[cam.id] = session;
        } else {
          await session.open(url);
        }
        _sessionErrors[cam.id] = null;
        if (autoPlay) {
          await session.play();
        }
      } catch (e) {
        _sessionErrors[cam.id] = 'Error de conexión';
      }
    } else {
      final session = _sessions.remove(cam.id);
      session?.dispose();
      final proxy = _proxies.remove(cam.id);
      proxy?.dispose();
    }
    if (mounted) setState(() {});
  }

  void _startPlayheadTimer() {
    _playheadTimer?.cancel();
    _playheadTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isPlaying || !mounted) return;
      setState(() {
        _currentSeconds += 1.0;
        if (_currentSeconds >= 86400.0) {
          _currentSeconds = 0.0;
          _stop();
        }
      });
    });
  }

  void _play() {
    if (_sessions.isEmpty) {
      _seekTo(_currentSeconds, autoPlay: true);
      return;
    }
    for (final s in _sessions.values) {
      s.play();
    }
    setState(() => _isPlaying = true);
    _startPlayheadTimer();
  }

  void _pause() {
    for (final s in _sessions.values) {
      s.pause();
    }
    setState(() => _isPlaying = false);
    _playheadTimer?.cancel();
  }

  void _stop() {
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
    setState(() => _isPlaying = false);
    _playheadTimer?.cancel();
  }

  void _step(int secondsDelta) {
    final next = (_currentSeconds + secondsDelta).clamp(0.0, 86400.0);
    _seekTo(next, autoPlay: _isPlaying);
  }

  void _toggleMute() {
    final next = !_muted;
    for (final s in _sessions.values) {
      s.setMuted(next);
    }
    setState(() => _muted = next);
  }

  void _toggleFocus(String cameraId) {
    setState(() {
      _focusedCameraId = (_focusedCameraId == cameraId) ? null : cameraId;
    });
  }

  void _openDay(DateTime day) {
    setState(() => _selectedDay = day);
    _loadSegmentsForDay(day);
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_viewportMonth.year, _viewportMonth.month + delta, 1);
    setState(() => _viewportMonth = next);
    _loadMonth(next);
  }

  // ------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reproducción de Grabaciones')),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white38),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(10),
        const SingleActivator(LogicalKeyboardKey.mediaRewind): () => _step(-60),
        const SingleActivator(LogicalKeyboardKey.mediaFastForward): () => _step(60),
        const SingleActivator(LogicalKeyboardKey.mediaPlay): _play,
        const SingleActivator(LogicalKeyboardKey.mediaPause): _pause,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () {
          if (_isPlaying) {
            _pause();
          } else {
            _play();
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090A0D),
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 20),
              SizedBox(width: 8),
              Text(
                'Reproducción de Grabaciones',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.today_outlined),
              tooltip: 'Ir a hoy',
              onPressed: () => _openDay(_today),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 760;
            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 300, child: _buildLeftPanel()),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Color(0xFF1B1E26),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDateSwitcher(),
                        Expanded(child: _buildVideoArea()),
                        _buildControlsBar(),
                        SizedBox(
                          height: (40.0 + _selectedCameras.length * 28.0).clamp(
                            90.0,
                            155.0,
                          ),
                          child: _buildTimeline(),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDateSwitcher(),
                  Expanded(flex: 5, child: _buildVideoArea()),
                  _buildControlsBar(),
                  SizedBox(height: 100, child: _buildTimeline()),
                  Expanded(flex: 4, child: _buildLeftPanel()),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildDateSwitcher() {
    final prevDay = _selectedDay.subtract(const Duration(days: 1));
    final nextDay = _selectedDay.add(const Duration(days: 1));
    final canGoNext = !nextDay.isAfter(_today);
    final isToday = _selectedDay.year == _today.year &&
        _selectedDay.month == _today.month &&
        _selectedDay.day == _today.day;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF0F1116),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TvFocusable(
            borderRadius: BorderRadius.circular(6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            backgroundColor: const Color(0xFF1B1E26),
            onTap: () => _openDay(prevDay),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text('◀ Anterior', style: TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF161A22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2B3240)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isToday ? Icons.today : Icons.calendar_month,
                  size: 15,
                  color: const Color(0xFF00E5FF),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selectedDay.day} ${_monthName(_selectedDay.month)} ${_selectedDay.year}'
                  '${isToday ? ' (Hoy)' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          TvFocusable(
            borderRadius: BorderRadius.circular(6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            backgroundColor: canGoNext ? const Color(0xFF1B1E26) : Colors.transparent,
            onTap: canGoNext ? () => _openDay(nextDay) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Siguiente ▶',
                  style: TextStyle(
                    color: canGoNext ? Colors.white : Colors.white24,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: canGoNext ? Colors.white : Colors.white24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Panel Izquierdo
  Widget _buildTargetTypeCard() {
    return Card(
      color: const Color(0xFF14171E),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.filter_alt_outlined, size: 16, color: Color(0xFFFFB300)),
                SizedBox(width: 6),
                Text(
                  'Buscar por tipo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTypeChip('', 'Todos'),
                for (final t in _targetTypes) ...[
                  const SizedBox(width: 6),
                  _buildTypeChip(t, _targetTypeLabel(t)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, String label) {
    final selected = _selectedTargetType == type;
    return TvFocusable(
      borderRadius: BorderRadius.circular(6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      backgroundColor: selected ? const Color(0xFFFFB300) : const Color(0xFF1B1E26),
      onTap: () {
        setState(() => _selectedTargetType = (type.isEmpty) ? null : type);
        _markers.clear();
        _loadMonth(_viewportMonth);
        _loadSegmentsForDay(_selectedDay);
      },
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  static String _targetTypeLabel(String type) {
    switch (type) {
      case 'human':
        return 'Humano';
      case 'vehicle':
        return 'Vehículo';
      case 'face':
        return 'Rostro';
      default:
        return type[0].toUpperCase() + type.substring(1);
    }
  }

  Widget _buildLeftPanel() {
    return Container(
      color: const Color(0xFF0F1116),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          if (_targetTypes.isNotEmpty) ...[
            _buildTargetTypeCard(),
            const SizedBox(height: 8),
          ],
          _buildCameraSelectorCard(),
          const SizedBox(height: 8),
          _buildCalendarCard(),
        ],
      ),
    );
  }

  Widget _buildCameraSelectorCard() {
    final allCameras = context.watch<AppState>().allCameras;

    return Card(
      color: const Color(0xFF14171E),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.videocam_outlined,
                  size: 16,
                  color: Color(0xFF2F9BFF),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Cámaras',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_selectedCameras.length}/4 activas',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: allCameras.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFF1F232B)),
                itemBuilder: (context, idx) {
                  final cam = allCameras[idx];
                  final selIdx = _selectedCameras.indexWhere(
                    (c) => c.id == cam.id,
                  );
                  final isSelected = selIdx >= 0;
                  final trackColor = isSelected
                      ? _trackColors[selIdx % _trackColors.length]
                      : null;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: TvFocusable(
                      borderRadius: BorderRadius.circular(6),
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 6,
                      ),
                      onTap: () => _toggleCamera(cam),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 18,
                            color: isSelected
                                ? (trackColor ?? const Color(0xFF2F9BFF))
                                : Colors.white38,
                          ),
                          const SizedBox(width: 8),
                          if (isSelected)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: trackColor,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              cam.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            'CH${cam.channel}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard() {
    final year = _viewportMonth.year, month = _viewportMonth.month;
    final markerKey = _markerKey(_viewportMonth);
    final markers = _markers[markerKey];
    final loading = _loadingMonths.contains(markerKey);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // Lun=0

    return Card(
      color: const Color(0xFF14171E),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_month,
                  size: 16,
                  color: Color(0xFF4CAF50),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Fecha',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  _fmtDay(_selectedDay),
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    '${_monthName(month)} $year',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['L', 'M', 'X', 'J', 'V', 'S', 'D']
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 4),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 7,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              children: [
                for (var i = 0; i < firstWeekday; i++) const SizedBox.shrink(),
                for (var d = 1; d <= daysInMonth; d++)
                  _buildDayCell(d, markers?[d] ?? false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(int day, bool hasRecording) {
    final selected =
        _selectedDay.year == _viewportMonth.year &&
        _selectedDay.month == _viewportMonth.month &&
        _selectedDay.day == day;
    final isFuture =
        _viewportMonth.year > _today.year ||
        (_viewportMonth.year == _today.year &&
            (_viewportMonth.month > _today.month ||
                (_viewportMonth.month == _today.month && day > _today.day)));

    return TvFocusable(
      scaleOnFocus: 1.15,
      borderRadius: BorderRadius.circular(4),
      onTap: isFuture
          ? null
          : () => _openDay(
              DateTime(_viewportMonth.year, _viewportMonth.month, day),
            ),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2F9BFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? Colors.black
                    : isFuture
                    ? Colors.white24
                    : Colors.white,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (hasRecording)
              Positioned(
                bottom: 1,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Colors.black87 : const Color(0xFF4CAF7D),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- Área de Video
  Widget _buildVideoArea() {
    if (_selectedCameras.isEmpty) {
      return const Center(
        child: Text(
          'Selecciona al menos una cámara en el panel izquierdo',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    if (_focusedCameraId != null) {
      final cam =
          _selectedCameras.where((c) => c.id == _focusedCameraId).firstOrNull ??
          _selectedCameras.first;
      final idx = _selectedCameras.indexOf(cam);
      final color = _trackColors[idx % _trackColors.length];
      return _buildCameraTileWrapper(cam, color, isSolo: true);
    }

    if (_selectedCameras.length == 1) {
      return _buildCameraTileWrapper(
        _selectedCameras.first,
        _trackColors.first,
        isSolo: true,
      );
    }

    // Cuadrícula 2x2 para 2 a 4 cámaras
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = _selectedCameras.length;
          final crossAxis = (count == 2 && constraints.maxWidth < 600) ? 1 : 2;

          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxis,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
              childAspectRatio: 16 / 9,
            ),
            itemCount: count,
            itemBuilder: (context, index) {
              final cam = _selectedCameras[index];
              final color = _trackColors[index % _trackColors.length];
              return _buildCameraTileWrapper(cam, color, isSolo: false);
            },
          );
        },
      ),
    );
  }

  Widget _buildCameraTileWrapper(
    Camera cam,
    Color trackColor, {
    required bool isSolo,
  }) {
    final session = _sessions[cam.id];
    final error = _sessionErrors[cam.id];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF08090C),
        border: Border.all(
          color: _focusedCameraId == cam.id
              ? trackColor
              : const Color(0xFF1B1E26),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraTile(
            session: session,
            name: cam.name,
            showLabel: false,
            rounded: false,
            onTap: () => _toggleFocus(cam.id),
          ),
          if (session == null && error == null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.pause_circle_outline,
                      size: 14,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Sin grabación en ${_fmtTimeSec(_currentSeconds)}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (error != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            ),
          Positioned(
            top: 4,
            left: 6,
            right: 6,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: trackColor,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    cam.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _toggleFocus(cam.id),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Icon(
                      _focusedCameraId == cam.id
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Barra de Controles
  Widget _buildControlsBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF12141A),
        border: Border(
          top: BorderSide(color: Color(0xFF1B1E26), width: 1),
          bottom: BorderSide(color: Color(0xFF1B1E26), width: 1),
        ),
      ),
      child: Row(
        children: [
          _TvControlButton(
            tooltip: 'Retroceder 1 minuto',
            onTap: () => _step(-60),
            child: const Text('-1m', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          _TvControlButton(
            tooltip: 'Retroceder 10 segundos',
            onTap: () => _step(-10),
            child: const Text('-10s', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          _TvControlButton(
            backgroundColor: const Color(0xFF00E5FF),
            tooltip: _isPlaying ? 'Pausar' : 'Reproducir',
            onTap: _isPlaying ? _pause : _play,
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              size: 20,
              color: Colors.black,
            ),
          ),
          _TvControlButton(
            tooltip: 'Avanzar 10 segundos',
            onTap: () => _step(10),
            child: const Text('+10s', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          _TvControlButton(
            tooltip: 'Avanzar 1 minuto',
            onTap: () => _step(60),
            child: const Text('+1m', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4),
          _TvControlButton(
            tooltip: 'Detener',
            onTap: _stop,
            child: const Icon(Icons.stop, size: 16, color: Colors.white70),
          ),
          _TvControlButton(
            tooltip: _muted ? 'Activar audio' : 'Silenciar',
            onTap: _toggleMute,
            child: Icon(
              _muted ? Icons.volume_off : Icons.volume_up,
              size: 16,
              color: _muted ? Colors.white54 : const Color(0xFF00E5FF),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.access_time,
                  size: 14,
                  color: Color(0xFF00E5FF),
                ),
                const SizedBox(width: 6),
                Text(
                  _fmtTimeSec(_currentSeconds),
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TvControlButton(
            tooltip: _focusedCameraId != null ? 'Ver cuadrícula' : 'Maximizar primera',
            onTap: () {
              setState(() {
                _focusedCameraId = (_focusedCameraId != null)
                    ? null
                    : _selectedCameras.firstOrNull?.id;
              });
            },
            child: Icon(
              _focusedCameraId != null ? Icons.grid_view : Icons.crop_square,
              size: 16,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Timeline
  Widget _buildTimeline() {
    final tracks = [
      for (var i = 0; i < _selectedCameras.length; i++)
        TimelineTrack(
          id: _selectedCameras[i].id,
          label: _selectedCameras[i].name,
          color: _trackColors[i % _trackColors.length],
          segments: _cameraSegments[_selectedCameras[i].id] ?? [],
        ),
    ];

    return Stack(
      children: [
        TimelineWidget(
          tracks: tracks,
          selectedDay: _selectedDay,
          currentSeconds: _currentSeconds,
          onSeek: (sec) => _seekTo(sec, autoPlay: _isPlaying),
          onScrubbing: (sec) => setState(() => _currentSeconds = sec),
        ),
        if (_loadingSegments)
          const Positioned(
            top: 4,
            right: 8,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white38,
              ),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------- Formateadores
  String _monthName(int m) => const [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ][m - 1];

  static String _fmtDay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtTimeSec(double totalSeconds) {
    final sec = totalSeconds.toInt();
    final h = (sec ~/ 3600) % 24;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _playheadTimer?.cancel();
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
    for (final p in _proxies.values) {
      p.dispose();
    }
    _proxies.clear();
    super.dispose();
  }
}

class _TvControlButton extends StatelessWidget {
  const _TvControlButton({
    required this.child,
    required this.onTap,
    this.tooltip,
    this.backgroundColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TvFocusable(
        borderRadius: BorderRadius.circular(6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        backgroundColor: backgroundColor ?? const Color(0xFF1B1E26),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

