import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/camera_model.dart';
import '../../models/device_model.dart';
import '../../models/recording_models.dart';
import '../../services/hikvision_service.dart';
import '../../services/rtsp_url_builder.dart';
import '../../state/app_state.dart';
import 'playback_page.dart';
import 'timeline_widget.dart';

String monthKeyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key, required this.deviceId, required this.channel});

  final String deviceId;
  final int channel;

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  Device? _device;
  HikvisionService? _service;
  Duration _offset = Duration.zero;
  bool _ready = false;

  late DateTime _today; // día local del dispositivo
  late DateTime _selectedDay;
  DateTime _viewportMonth = DateTime.now();

  final Map<String, Map<int, bool>> _markers = {};
  final Set<String> _loadingMonths = {};
  List<RecordingSegment> _segments = [];
  bool _loadingSegments = false;

  @override
  void initState() {
    super.initState();
    final app = Provider.of<AppState>(context, listen: false);
    _device = app.deviceById(widget.deviceId);
    _service = HikvisionService(_device!);
    _init();
  }

  Future<void> _init() async {
    try {
      _offset = await _service!.fetchDeviceUtcOffset();
    } catch (_) {
      _offset = Duration.zero;
    }
    _today = HikvisionService.toDeviceLocal(DateTime.now().toUtc(), _offset);
    final dateOnly = DateTime(_today.year, _today.month, _today.day);
    _selectedDay = dateOnly;
    _viewportMonth = dateOnly;
    if (mounted) {
      setState(() => _ready = true);
      _loadMonth(dateOnly);
      _loadSegments(_selectedDay);
    }
  }

  // --------------------------------------------------------- consultas
  Future<void> _loadMonth(DateTime monthDay) async {
    final key = monthKeyOf(monthDay);
    if (_markers.containsKey(key) || _loadingMonths.contains(key)) return;
    final service = _service;
    if (service == null) return;
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
      try {
        final list = await service
            .searchRecordings(channel: widget.channel, start: day, end: end, maxResults: 1);
        map[d] = list.isNotEmpty;
      } catch (_) {
        map[d] = false;
      }
    }

    // Concurrencia limitada (lotes de 5) para no saturar al DVR.
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

  Future<void> _loadSegments(DateTime day) async {
    final service = _service;
    if (service == null) return;
    setState(() {
      _loadingSegments = true;
      _segments = [];
    });
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day, 23, 59, 59);
    try {
      final list = await service.searchRecordings(
        channel: widget.channel,
        start: start,
        end: end,
        maxResults: 300,
      );
      if (mounted) {
        setState(() {
          _segments = list;
          _loadingSegments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingSegments = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'No se pudo consultar grabaciones: ${e.toString().replaceFirst('IsapiException:', '')}'),
        ));
      }
    }
  }

  void _openDay(DateTime day) {
    setState(() => _selectedDay = day);
    _loadSegments(day);
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_viewportMonth.year, _viewportMonth.month + delta, 1);
    setState(() => _viewportMonth = next);
    _loadMonth(next);
  }

  void _play(RecordingSegment seg) {
    final device = _device;
    if (device == null) return;
    final start = HikvisionService.toDeviceLocal(seg.startUtc, _offset);
    final end = HikvisionService.toDeviceLocal(seg.endUtc, _offset);
    final url = RtspUrlBuilder.fromPlaybackUri(
          device,
          seg.playbackUri,
          startLocal: start,
          endLocal: end,
        ) ??
        RtspUrlBuilder.playback(device, widget.channel, start, end);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaybackPage(
        url: url,
        title: '${_fmtDate(start)} · ${_fmtTime(start)} – ${_fmtTime(end)}',
      ),
    ));
  }

  // ------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('Grabaciones')),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white38),
        ),
      );
    }
    final deviceName = _device?.name ?? widget.deviceId;
    return Scaffold(
      appBar: AppBar(
        title: Text('Grabaciones · $deviceName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Hoy',
            onPressed: () => _openDay(_today),
          ),
        ],
      ),
      body: Column(
        children: [
          _calendarCard(),
          _timelineCard(),
        ],
      ),
    );
  }

  Widget _calendarCard() {
    final year = _viewportMonth.year, month = _viewportMonth.month;
    final markers = _markers[monthKeyOf(_viewportMonth)];
    final loading = _loadingMonths.contains(monthKeyOf(_viewportMonth));
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // lun=0

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftMonth(-1),
                ),
                Expanded(
                  child: Text(
                    '${_monthName(month)} $year',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['L', 'M', 'X', 'J', 'V', 'S', 'D']
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                        ),
                      ))
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
                  _dayCell(d, markers?[d] ?? false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(int day, bool hasRecording) {
    final selected =
        _selectedDay.year == _viewportMonth.year &&
        _selectedDay.month == _viewportMonth.month &&
        _selectedDay.day == day;
    final isFuture =
        _viewportMonth.year > _today.year ||
        (_viewportMonth.year == _today.year &&
            (_viewportMonth.month > _today.month ||
                (_viewportMonth.month == _today.month && day > _today.day)));

    return InkWell(
      onTap: isFuture
          ? null
          : () => _openDay(DateTime(_viewportMonth.year, _viewportMonth.month, day)),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2F9BFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
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
                bottom: 2,
                child: Container(
                  width: 5,
                  height: 5,
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

  Widget _timelineCard() {
    final device = _device;
    final camera = device == null
        ? null
        : context.read<AppState>().allCameras.firstWhere(
              (c) => c.deviceId == widget.deviceId && c.channel == widget.channel,
              orElse: () => Camera.forDevice(device, widget.channel),
            );

    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: Colors.white54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      camera?.name ?? 'Canal ${widget.channel}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _fmtDay(_selectedDay),
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loadingSegments)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white38),
                  ),
                )
              else if (_segments.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('Sin grabaciones este día',
                        style: TextStyle(color: Colors.white38)),
                  ),
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                    child: TimelineWidget(
                      segments: _segments,
                      offset: _offset,
                      onSegmentTap: _play,
                    ),
                  ),
                      const SizedBox(height: 8),
                      Text(
                        '${_segments.length} segmentos · ${_fmtTime(HikvisionService.toDeviceLocal(_segments.first.startUtc, _offset))} – ${_fmtTime(HikvisionService.toDeviceLocal(_segments.last.endUtc, _offset))}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- helpers
  String _monthName(int m) => const [
        'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
        'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
      ][m - 1];

  static String _fmtDay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  static String _fmtDate(DateTime d) => _fmtDay(d);

  @override
  void dispose() {
    super.dispose();
  }
}