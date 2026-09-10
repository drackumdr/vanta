import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'recordings/recordings_page.dart';
import '../widgets/camera_tile.dart';

class FullscreenPage extends StatefulWidget {
  const FullscreenPage({super.key, required this.cameraId});

  final String cameraId;

  @override
  State<FullscreenPage> createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<FullscreenPage> {
  bool _controls = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().setFocusCamera(widget.cameraId);
    });
  }

  @override
  void dispose() {
    context.read<AppState>().setFocusCamera(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final camera = app.cameraById(widget.cameraId);
    final session =
        app.streams.snapshot(widget.cameraId)?.session;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controls = !_controls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraTile(
              session: session,
              name: camera?.name ?? '',
              showLabel: false,
              fullscreen: true,
            ),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              camera?.name ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.grid_view, size: 14,
                              color: Colors.white54),
                          const SizedBox(width: 4),
                          const Text('Principal',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: camera == null
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => RecordingsPage(
                                          deviceId: camera.deviceId,
                                          channel: camera.channel,
                                        ),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.history, size: 16),
                            label: const Text('Grabaciones'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
