import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart' as wm;

import 'app.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    mk.MediaKit.ensureInitialized();
    wm.windowManager.ensureInitialized();
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..load(),
      child: const VantaApp(),
    ),
  );
}
